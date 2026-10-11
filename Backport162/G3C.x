// G3C.x  (0.7.0)  Top-affordance "Zoom" (and the Zoom keyboard shortcut) = faithful port of the iPadOS 16.2 request.
//
// History: 0.6.5 hooked -[SBWorkspaceApplicationSceneTransitionContext setRequestedLayoutAttributes:forEntity:] and rewrote the attributes that
// the 16.0 request block produced (armed for 3 s after action type 9).  That was a hack on top of 16.0 behaviour.  0.7.0 replaces it with 16.2's
// own implementation of the action (details and addresses: specs/AUDIT-ZOOM-0.6.5.md, specs/PORT-G3-0.7.0.md).
//
// 16.2 -[SBMedusaDecoratedDeviceApplicationSceneViewController _topAffordanceViewController:handleActionType:transitionSource:] (0x1c77ccb6c),
// case 9 (the "Zoom"/"Unzoom" item, UIAction block 0x1c790db38; 16.0 0x1c632ba50 / block 0x1c645abb8):
//     [topAffordanceVC dismissAnimated:YES];
//     [[SBWorkspace mainWorkspace] requestTransitionWithOptions:0 displayConfiguration:[[handle _windowScene] _fbsDisplayConfiguration]
//         builder:^(req){ req.source = transitionSource;                                              // block 0x1c77cd238 (16.0 0x1c632c0ec: same)
//             [req modifyApplicationContext:^(ctx){                                                    // block 0x1c77cd2e8 (16.0 0x1c632c18c: toggle)
//                 e = [[SBDeviceApplicationSceneEntity alloc] initWithApplicationSceneHandle:handle];
//                 [ctx setEntities:@[e] withPolicy:0 centerEntity:nil floatingEntity:nil];             // NEW in 16.2
//                 [ctx _setRequestedFrontmostEntity:e];
//                 mask = [handle _supportedSizingPoliciesForContentOrientation:[handle currentInterfaceOrientation]
//                                                           containerOrientation:[[windowScene switcherController] interfaceOrientation]];
//                 a = [[ctx requestedLayoutAttributesForEntity:e] attributesByModifyingSizingPolicy:SBDisplayItemSizingPolicyAllowingLargestSize(mask)];
//                 a = [a attributesByModifyingAttributedSize:SBDisplayItemAttributedSizeUnspecified()];                          // NEW
//                 a = [a attributesByModifyingAttributedUserSizeBeforeOverlapping:SBDisplayItemAttributedSizeUnspecified()];     // NEW
//                 [ctx setRequestedLayoutAttributes:a forEntity:e]; [ctx setFencesAnimations:YES]; }]; }
//             validator:nil];
// There is no AllowingSmallestSize toggle in 16.2 (16.0 toggled the policy only).
//
// Keyboard shortcut: -[SpringBoard _handleToggleMaximizationKeyShortcut:] (16.0 0x1c5ee5a54; renamed _handleEnterFullScreenKeyShortcut: in 16.2,
// 0x1c7359b1c, same body) -> SBSwitcherController performKeyboardShortcutAction:0x11 -> coordinator -> SBFluidSwitcherViewController
// performKeyboardShortcutAction: (16.0 0x1c5fc2070 / 16.2 0x1c743ace4, jump-table slot for 0x11 forwards to the live content overlay coordinator in
// both) -> SBFullScreenSwitcherLiveContentOverlayCoordinator performSwitcherKeyboardShortcutAction: (16.0 0x1c60500c4 / 16.2 0x1c74cbfb0, identical)
// -> SBMedusaDecoratedDeviceApplicationSceneViewController performSwitcherKeyboardShortcutAction: (16.0 0x1c632aa40 / 16.2 0x1c77cbad0, identical):
// action 0x11 -> [self _topAffordanceViewController:vc handleActionType:9 transitionSource:0x33].  Every link of the chain is the same code in 16.0
// and 16.2, and it ends in the handler above, so replacing case 9 of the handler covers BOTH the menu item (source 0x32) and the shortcut (0x33).
//
// Data model: the 16.2 attributed-size API (attributesByModifyingAttributedSize: / ...AttributedUserSizeBeforeOverlapping:) and the handle's
// _supportedSizingPoliciesForContentOrientation:containerOrientation: are emulated on the 16.0 classes by G2B.m.  Largest = (mask & 4) ? 2 : (mask >> 1) & 1
// (identical code in 16.0 0x1c649d490 and 16.2 0x1c795431c).  Unspecified = {size {0,0}, referenceBounds CGRectNull, type 0} (16.2 0x1c75cedc4).
// No arming window: the request is built synchronously from the live handle, so it works for a never-windowed item as well.
// Switch: "g3c" (Backport162.off.g3c).  Last-line guards (selector missing because group 2b is off, nil handle) log under BP_LogEnabled() and fall to %orig.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <string.h>
#import <time.h>

#import "BP.h"

#pragma clang diagnostic ignored "-Wundeclared-selector"

// interface declarations for the hooked classes (Logos only emits @class, ARC needs a visible @interface to message them)
@interface SBMedusaDecoratedDeviceApplicationSceneViewController : UIViewController @end

@interface NSObject (BPG3C)
- (id)_windowScene;
- (id)_fbsDisplayConfiguration;
- (id)switcherController;
- (long long)interfaceOrientation;
- (long long)currentInterfaceOrientation;
- (void)dismissAnimated:(BOOL)animated;
- (void)setSource:(long long)source;
- (void)modifyApplicationContext:(id)block;
- (void)setEntities:(id)entities withPolicy:(long long)policy centerEntity:(id)center floatingEntity:(id)floating;
- (void)_setRequestedFrontmostEntity:(id)entity;
- (id)requestedLayoutAttributesForEntity:(id)entity;
- (void)setRequestedLayoutAttributes:(id)attrs forEntity:(id)entity;
- (void)setFencesAnimations:(BOOL)fences;
- (id)attributesByModifyingSizingPolicy:(long long)policy;
- (id)initWithApplicationSceneHandle:(id)handle;
+ (id)mainWorkspace;
- (BOOL)requestTransitionWithOptions:(unsigned long long)options displayConfiguration:(id)cfg builder:(id)builder validator:(id)validator;
@end

// SBDisplayItemAttributedSize (16.2 struct, G2B.m BP2BAttrSize)
typedef struct { CGSize normalizedSize; CGRect referenceBounds; long long semanticSizeType; } BPG3CAttrSize;

static BOOL G3C_On(void) { return BP_OnName("g3c"); }

static id G3C_Ivar(id obj, const char *name) {
    Ivar iv = obj ? class_getInstanceVariable(object_getClass(obj), name) : NULL;
    const char *enc = iv ? ivar_getTypeEncoding(iv) : NULL;
    return (enc && enc[0] == '@') ? object_getIvar(obj, iv) : nil;
}

// SBDisplayItemAttributedSizeUnspecified()  16.2 0x1c75cedc4
static BPG3CAttrSize G3C_Unspecified(void) {
    BPG3CAttrSize s; s.normalizedSize = CGSizeZero; s.referenceBounds = CGRectNull; s.semanticSizeType = 0; return s;
}

// SBDisplayItemSizingPolicyAllowingLargestSize(mask)  16.2 0x1c795431c == 16.0 0x1c649d490
static long long G3C_LargestPolicy(unsigned long long mask) { return (mask & 4) ? 2 : (long long)((mask >> 1) & 1); }

// The body of 16.2 block 0x1c77cd2e8.  Returns NO (and logs) only when a selector the faithful path needs is missing (last-line guard).
static BOOL G3C_ZoomRequest(id ctx, id handle, id windowScene) {
    Class entC = NSClassFromString(@"SBDeviceApplicationSceneEntity");
    SEL initS = @selector(initWithApplicationSceneHandle:);
    SEL supS = NSSelectorFromString(@"_supportedSizingPoliciesForContentOrientation:containerOrientation:");
    SEL asS = NSSelectorFromString(@"attributesByModifyingAttributedSize:");
    SEL usS = NSSelectorFromString(@"attributesByModifyingAttributedUserSizeBeforeOverlapping:");
    if (!entC || ![entC instancesRespondToSelector:initS] || ![ctx respondsToSelector:@selector(setEntities:withPolicy:centerEntity:floatingEntity:)]
        || ![handle respondsToSelector:supS]) {
        BP_Log(@"[g3c] zoom: required 16.2 selector missing (entity %d setEntities %d supportedPolicies %d)", entC != nil, [ctx respondsToSelector:@selector(setEntities:withPolicy:centerEntity:floatingEntity:)], [handle respondsToSelector:supS]);
        return NO;
    }
    id entity = ((id (*)(id, SEL, id))objc_msgSend)([entC alloc], initS, handle);
    if (!entity) return NO;
    [ctx setEntities:@[ entity ] withPolicy:0 centerEntity:nil floatingEntity:nil];
    [ctx _setRequestedFrontmostEntity:entity];
    long long contentOri = [handle currentInterfaceOrientation];
    long long containerOri = [[windowScene switcherController] interfaceOrientation];
    unsigned long long mask = ((unsigned long long (*)(id, SEL, long long, long long))objc_msgSend)(handle, supS, contentOri, containerOri);
    id a = [ctx requestedLayoutAttributesForEntity:entity];
    a = [a attributesByModifyingSizingPolicy:G3C_LargestPolicy(mask)];
    if ([a respondsToSelector:asS] && [a respondsToSelector:usS]) {
        a = ((id (*)(id, SEL, BPG3CAttrSize))objc_msgSend)(a, asS, G3C_Unspecified());
        a = ((id (*)(id, SEL, BPG3CAttrSize))objc_msgSend)(a, usS, G3C_Unspecified());
    } else {
        BP_Log(@"[g3c] zoom: attributed-size API missing, 16.0 data model (size 0 == Unspecified) used");
        a = ((id (*)(id, SEL, CGSize))objc_msgSend)(a, @selector(attributesByModifyingSize:), CGSizeZero);
        SEL u0 = NSSelectorFromString(@"attributesByModifyingUserConfiguredSizeBeforeOverlapping:");
        if ([a respondsToSelector:u0]) a = ((id (*)(id, SEL, CGSize))objc_msgSend)(a, u0, CGSizeZero);
    }
    BP_Log(@"[g3c] zoom: policy mask %llu -> %lld (content %lld container %lld), size Unspecified", mask, G3C_LargestPolicy(mask), contentOri, containerOri);
    [ctx setRequestedLayoutAttributes:a forEntity:entity];
    [ctx setFencesAnimations:YES];
    return YES;
}

%group G3C_Zoom

%hook SBMedusaDecoratedDeviceApplicationSceneViewController

// 16.0 0x1c632ba50 / 16.2 0x1c77ccb6c.  Case 9 only; every other action type is the same code in 16.0 and 16.2 (%orig).
- (void)_topAffordanceViewController:(id)vc handleActionType:(long long)type transitionSource:(long long)source {
    if (type != 9 || !G3C_On()) {
        %orig(vc, type, source);
        return;
    }
    id handle = G3C_Ivar((id)self, "_deviceApplicationSceneHandle");
    id windowScene = [handle respondsToSelector:@selector(_windowScene)] ? [handle _windowScene] : nil;
    Class wsC = NSClassFromString(@"SBWorkspace");
    id workspace = [wsC respondsToSelector:@selector(mainWorkspace)] ? [wsC mainWorkspace] : nil;
    id cfg = [windowScene respondsToSelector:@selector(_fbsDisplayConfiguration)] ? [windowScene _fbsDisplayConfiguration] : nil;
    Class entC = NSClassFromString(@"SBDeviceApplicationSceneEntity"), ctxC = NSClassFromString(@"SBWorkspaceApplicationSceneTransitionContext");
    BOOL api = entC && ctxC && [ctxC instancesRespondToSelector:@selector(setEntities:withPolicy:centerEntity:floatingEntity:)]
        && [handle respondsToSelector:NSSelectorFromString(@"_supportedSizingPoliciesForContentOrientation:containerOrientation:")];
    if (!api || !handle || !windowScene || !cfg || ![workspace respondsToSelector:@selector(requestTransitionWithOptions:displayConfiguration:builder:validator:)]) {
        BP_Log(@"[g3c] handleActionType 9: api %d handle %d windowScene %d displayConfiguration %d workspace %d, stock path", api, handle != nil, windowScene != nil, cfg != nil, workspace != nil);
        %orig(vc, type, source);
        return;
    }
    BP_Log(@"[g3c] handleActionType 9 (Zoom) source 0x%llx", (unsigned long long)source);
    if ([vc respondsToSelector:@selector(dismissAnimated:)]) [vc dismissAnimated:YES];
    id builder = ^(id req) {                                                // 16.2 block 0x1c77cd238
        [req setSource:source];
        [req modifyApplicationContext:^(id ctx) {                           // 16.2 block 0x1c77cd2e8
            (void)G3C_ZoomRequest(ctx, handle, windowScene);
        }];
    };
    [workspace requestTransitionWithOptions:0 displayConfiguration:cfg builder:builder validator:nil];
}

%end

%end // G3C_Zoom

void G3C_Setup(void) {
    %init(G3C_Zoom);
}
