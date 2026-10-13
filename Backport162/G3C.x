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
// The literal 16.2 block has no AllowingSmallestSize toggle (16.0 toggled the policy only); the un-zoom direction (second press) is added on top, see G3C_ZoomRequest
// (re-investigation 0.7.1: no 16.2 code path could be found that leaves the zoomed state, the title/image logic is the only isZoomed consumer).
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
@interface SBMainDisplayLayoutStateManager : NSObject @end

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
- (long long)sizingPolicy;
- (id)layoutState;
- (id)displayItemRepresentation;
- (id)layoutAttributesForItem:(id)item;
- (void)setRequestedLayoutAttributes:(id)attrs forEntity:(id)entity;
- (void)setFencesAnimations:(BOOL)fences;
- (void)setRequestedPeekConfiguration:(long long)peek;
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
// SBDisplayItemSizingPolicyAllowingSmallestSize(mask)  16.2 0x1c79542fc == 16.0 0x1c649d470
static long long G3C_SmallestPolicy(unsigned long long mask) { return (mask & 1) ? 0 : ((mask & 2) ? 1 : (long long)((mask >> 1) & 2)); }

// The COMMITTED attributes of the window (what is displayed), never the pending/requested ones: the current layout state of the window scene's switcher
// controller, app layout (or floating app layout) containing the window's display item.  The context's requestedLayoutAttributesForEntity: (filled by
// _setRequestedFrontmostEntity: from the previous layout state's element dictionary) holds the REQUESTED attributes of the last transition, which the calculator
// may have re-derived afterwards (device log 0c1bc38: requested policy 2, displayed snap-to-grid), so it is only used as the base of the new request.
static id G3C_CommittedAttrs(id windowScene, id handle) {
    id sc = [windowScene respondsToSelector:@selector(switcherController)] ? [windowScene switcherController] : nil;
    id ls = [sc respondsToSelector:@selector(layoutState)] ? [sc layoutState] : nil;
    id item = [handle respondsToSelector:@selector(displayItemRepresentation)] ? [handle displayItemRepresentation] : nil;
    if (!ls || !item) return nil;
    for (NSString *n in @[ @"appLayout", @"floatingAppLayout" ]) {
        SEL s = NSSelectorFromString(n);
        id layout = [ls respondsToSelector:s] ? ((id (*)(id, SEL))objc_msgSend)(ls, s) : nil;
        id a = [layout respondsToSelector:@selector(layoutAttributesForItem:)] ? [layout layoutAttributesForItem:item] : nil;
        if (a) return a;
    }
    return nil;
}
static long long G3C_CommittedPolicy(id windowScene, id handle) {
    id a = G3C_CommittedAttrs(windowScene, handle);
    return a ? [a sizingPolicy] : -1;
}

static char kG3CPreZoomSize;                                            // NSData(BPG3CAttrSize) of the window before it was zoomed, on the scene handle

// Zoom / Unzoom request (body of 16.2 block 0x1c77cd2e8 plus the un-zoom direction, see below).
//
// What 16.2 does (re-investigated 0.7.1): the block ALWAYS requests (Largest, Unspecified, Unspecified); there is no AllowingSmallestSize call in it, in the
// handler, or anywhere else (the only 16.2 callers of 0x1c79542fc / 0x1c795431c are the resize modifier, setLayoutRole:...sizingPolicy: and this block), no new
// reader of sizingPolicy exists, and the layout-state/calculator code that consumes the request is the same as 16.0 apart from the frame code (policy 2 resolves
// to the container only for an Unspecified size).  _isZoomed (= policy == Largest) only drives the menu title/image.  So the literal 16.2 code can zoom but
// never leaves the zoomed state through this item.  The product behaviour (second press windows the app again, title UNZOOM) is therefore reproduced here as
// the 16.0 toggle direction applied on top of the 16.2 attribute computation:
//   * current policy == Largest(mask)  ->  policy = Smallest(mask), size = the window size remembered when it was zoomed (if it was not full size) else
//                                          Unspecified (the calculator then resolves the 16.2 default window size), user size Unspecified
//   * otherwise                        ->  remember the current attributed size, then exactly the 16.2 request (Largest, Unspecified, Unspecified)
// Last-line guards (missing selector because group 2b is off) log under BP_LogEnabled() and use the 16.0 data model.
static BOOL G3C_ZoomRequest(id ctx, id handle, id windowScene) {
    Class entC = NSClassFromString(@"SBDeviceApplicationSceneEntity");
    SEL initS = @selector(initWithApplicationSceneHandle:);
    SEL supS = NSSelectorFromString(@"_supportedSizingPoliciesForContentOrientation:containerOrientation:");
    SEL asS = NSSelectorFromString(@"attributesByModifyingAttributedSize:");
    SEL usS = NSSelectorFromString(@"attributesByModifyingAttributedUserSizeBeforeOverlapping:");
    SEL getS = NSSelectorFromString(@"attributedSize");
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
    id cur = [ctx requestedLayoutAttributesForEntity:entity];                  // base of the request only
    long long largest = G3C_LargestPolicy(mask);
    long long committed = G3C_CommittedPolicy(windowScene, handle);           // the displayed state decides the direction
    BOOL zoomed = committed >= 0 ? committed == largest : [cur sizingPolicy] == largest;
    BOOL api = [cur respondsToSelector:asS] && [cur respondsToSelector:usS];
    BPG3CAttrSize size = G3C_Unspecified();
    long long policy = largest;
    if (zoomed) {
        policy = G3C_SmallestPolicy(mask);
        NSData *d = objc_getAssociatedObject(handle, &kG3CPreZoomSize);
        if (d.length == sizeof(BPG3CAttrSize)) {
            BPG3CAttrSize saved; [d getBytes:&saved length:sizeof saved];
            BOOL full = saved.normalizedSize.width == 1.0 && saved.normalizedSize.height == 1.0;     // a full size policy-0 window would be re-derived to Maximized (16.2 0x1c7954330)
            BOOL unspec = saved.normalizedSize.width == 0 && saved.normalizedSize.height == 0;
            if (!full && !unspec) size = saved;
        }
        objc_setAssociatedObject(handle, &kG3CPreZoomSize, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else if (api && [cur respondsToSelector:getS]) {
        BPG3CAttrSize now = ((BPG3CAttrSize (*)(id, SEL))objc_msgSend)(cur, getS);
        objc_setAssociatedObject(handle, &kG3CPreZoomSize, [NSData dataWithBytes:&now length:sizeof now], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    id a = [cur attributesByModifyingSizingPolicy:policy];
    if (api) {
        a = ((id (*)(id, SEL, BPG3CAttrSize))objc_msgSend)(a, asS, size);
        a = ((id (*)(id, SEL, BPG3CAttrSize))objc_msgSend)(a, usS, G3C_Unspecified());
    } else {
        BP_Log(@"[g3c] zoom: attributed-size API missing, 16.0 data model (size 0 == Unspecified) used");
        a = ((id (*)(id, SEL, CGSize))objc_msgSend)(a, @selector(attributesByModifyingSize:), size.normalizedSize);
        SEL u0 = NSSelectorFromString(@"attributesByModifyingUserConfiguredSizeBeforeOverlapping:");
        if ([a respondsToSelector:u0]) a = ((id (*)(id, SEL, CGSize))objc_msgSend)(a, u0, CGSizeZero);
    }
    BP_Log(@"[g3c] %s: policy mask %llu, committed %lld requested-base %lld -> %lld, size {%g, %g}, content %lld container %lld", zoomed ? "unzoom" : "zoom", mask, committed, (long long)[cur sizingPolicy], policy, size.normalizedSize.width, size.normalizedSize.height, contentOri, containerOri);
    [ctx setRequestedLayoutAttributes:a forEntity:entity];
    [ctx setFencesAnimations:YES];
    return YES;
}

// One Zoom/Unzoom transition request.  Verification (0.7.2): the committed layout is read again when the transition has had time to finish; if the committed
// policy did not change although the request was built (the transition was swallowed/overridden, device log 0c1bc38 press 1) and no newer press happened, the
// same request is issued once more (it recomputes the direction from the committed state, so it can never undo a request that did apply).
static uint64_t gG3CPressGen;
static void G3C_SendZoom(id workspace, id cfg, long long source, id handle, id windowScene, int attempt) {
    uint64_t gen = ++gG3CPressGen;
    long long before = G3C_CommittedPolicy(windowScene, handle);
    id builder = ^(id req) {                                                // 16.2 block 0x1c77cd238
        [req setSource:source];
        [req modifyApplicationContext:^(id ctx) {                           // 16.2 block 0x1c77cd2e8
            (void)G3C_ZoomRequest(ctx, handle, windowScene);
        }];
    };
    [workspace requestTransitionWithOptions:0 displayConfiguration:cfg builder:builder validator:nil];
    if (attempt >= 1) return;
    __weak id wh = handle, wws = windowScene, wwk = workspace;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        id h = wh, ws = wws, wk = wwk;
        if (!h || !ws || !wk || gen != gG3CPressGen) return;                // a newer press owns the state
        long long after = G3C_CommittedPolicy(ws, h);
        if (before >= 0 && after == before) {
            BP_Log(@"[g3c] zoom request had no effect (committed policy still %lld), repeating once", after);
            G3C_SendZoom(wk, cfg, source, h, ws, attempt + 1);
        }
    });
}

%group G3C_Zoom

%hook SBMedusaDecoratedDeviceApplicationSceneViewController

// 16.0 0x1c632ba50 / 16.2 0x1c77ccb6c.  Case 9 only; every other action type is the same code in 16.0 and 16.2 (%orig).
- (void)_topAffordanceViewController:(id)vc handleActionType:(long long)type transitionSource:(long long)source {
    BOOL zoom = type == 9 && G3C_On();
    BOOL addWin = type == 12 && BP_OnName("g3c_addwin");
    if (!zoom && !addWin) {
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
    if ((zoom && !api) || !handle || !windowScene || !cfg || ![workspace respondsToSelector:@selector(requestTransitionWithOptions:displayConfiguration:builder:validator:)]) {
        BP_Log(@"[g3c] handleActionType %lld: api %d handle %d windowScene %d displayConfiguration %d workspace %d, stock path", type, api, handle != nil, windowScene != nil, cfg != nil, workspace != nil);
        %orig(vc, type, source);
        return;
    }
    BP_Log(@"[g3c] handleActionType %lld (%s) source 0x%llx", type, zoom ? "Zoom" : "Add Another Window", (unsigned long long)source);
    if ([vc respondsToSelector:@selector(dismissAnimated:)]) [vc dismissAnimated:YES];
    if (addWin) {
        // 16.2 case 12 (blocks 0x1c77cd4a0 / 0x1c77cd4fc): source + requestedPeekConfiguration = 2 ONLY.  16.0 (0x1c632c290 / 0x1c632c2ec) also forced
        // requestedUnlockedEnvironmentMode = 3, which 16.2 dropped (the environment mode of the layout state stays as it is, e.g. on an extended display).
        id addBuilder = ^(id req) {
            [req setSource:source];
            [req modifyApplicationContext:^(id ctx) { [ctx setRequestedPeekConfiguration:2]; }];
        };
        [workspace requestTransitionWithOptions:0 displayConfiguration:cfg builder:addBuilder validator:nil];
        return;
    }
    G3C_SendZoom(workspace, cfg, source, handle, windowScene, 0);
}

%end

%end // G3C_Zoom

// ============================================================================================================
// Add Another Window with 2+ windows on the stage  (switch "g3c_addwin", sub-switch "g3c_peekmode")
// ============================================================================================================
// ROOT CAUSE.  The type-12 request only carries requestedPeekConfiguration = 2 (see the handler above).  What turns it into a layout state is
// -[SBMainDisplayLayoutStateManager _layoutStateForApplicationTransitionContext:] (16.0 0x1c5e23430, 16.2 0x1c72952ec) and that method CHANGED:
//   16.0 0x1c5e240e8..0x1c5e24138:  if (_SBPeekConfigurationIsValid(requestedPeek)) {
//                                       drop = ([[previousState elements] count] > 1) && chamoisWindowingUIEnabled;      // 0x1c5e240f4..0x1c5e24110
//                                       if (drop) { peek = none(1); mode = previousState.unlockedEnvironmentMode; spaceConfiguration = previous's } }
//                                   i.e. a stage that already holds two or more windows silently discards the peek: the transition ends with the identical layout
//                                   (log: "addwin: transition end ... modes 3->3 peek 1->1", N unchanged).  One window: the peek survives (mode 1, peek 2).
//   16.2 0x1c7295ffc..0x1c7296248:  no element-count test at all.  For chamois with a valid requested peek and NO peek in the previous state (0x1c7296014 ->
//                                   0x1c72961cc):  recents = [[self _recentAppLayouts] recentsIncludingHiddenAppLayouts:NO];
//                                                  unlockedEnvironmentMode = 1 + (recents.count >= 2);                   // 0x1c72961f4..0x1c7296218 (cinc), stored to
//                                                  the mode slot (the same slot 0x1c7297514 compares with 2), peek = the requested one.
//                                   (home screen to pick from when there is nothing else open, the app switcher with the peeking stage otherwise)
// 16.0 would also have left mode 1 for the one-window case (mode 0 + valid peek -> 1, 0x1c5e24c94), so the 16.2 mode rule is applied for both.
// The 16.0 method is a ~3300 instruction body that cannot be re-entered with a different decision, so it runs unchanged and its RESULT is corrected for exactly
// that case (same entities / space / attributes as the stock result, which for a peek request equals the previous state, only peek and mode set the 16.2 way).
@interface NSObject (BPG3CPeek)
- (id)_switcherControllerForDisplayIdentity:(id)identity;
- (id)displayIdentity;
- (BOOL)isChamoisWindowingUIEnabled;
- (id)_recentAppLayouts;
- (id)recentsIncludingHiddenAppLayouts:(BOOL)hidden;
- (long long)requestedPeekConfiguration;
- (void)setRequestedPeekConfiguration:(long long)cfg;
- (long long)peekConfiguration;
- (long long)unlockedEnvironmentMode;
- (id)previousLayoutState;
- (id)_initWithLayoutState:(id)state;
- (id)request;
- (id)activatingEntity;
- (void)setEntity:(id)entity forLayoutRole:(long long)role;
- (id)entityForLayoutRole:(long long)role;
- (void)_setRequestedFrontmostEntity:(id)entity;
- (id)entities;
- (id)previousEntities;
- (BOOL)isBackground;
- (long long)source;
- (long long)layoutRole;
- (BOOL)isHomeScreenEntity;
- (BOOL)isPreviousWorkspaceEntity;
- (BOOL)isEmptyWorkspaceEntity;
@end

// 16.0 0x1c5e23430..0x1c5e2351c: chamois = [[self _switcherControllerForDisplayIdentity:[request displayIdentity]] isChamoisWindowingUIEnabled]
// (the flag lives on the per-display switcher controller, NOT on SBMainWorkspace; request = [ctx request], previous = [ctx previousLayoutState])
static BOOL G3C_Chamois(id mgr, id ctx) {
    id rq = [ctx respondsToSelector:@selector(request)] ? [ctx request] : nil;
    id di = [rq respondsToSelector:@selector(displayIdentity)] ? [rq displayIdentity] : nil;
    id sc = [mgr respondsToSelector:@selector(_switcherControllerForDisplayIdentity:)] ? [mgr _switcherControllerForDisplayIdentity:di] : nil;
    return [sc respondsToSelector:@selector(isChamoisWindowingUIEnabled)] && [sc isChamoisWindowingUIEnabled];
}

// ---------------------------------------------------------------------------------------------------------------------------------------------------
// END OF THE PEEK (the app picked after "Add Another Window" joins the peeking stage).  Spec: specs/ADDWINDOW-PICK-0.7.4.md.
// 16.2 has a new branch in -_layoutStateForApplicationTransitionContext: (0x1c7296020..0x1c7296f6c; entry 0x1c7295ffc..0x1c7296030: chamois, requestedPeek == 0,
// previous state peeking, not background / source 0xe).  Pick case (0x1c7296908..0x1c7296f40): the picked entity goes to role 1 (0x1c7296d70; a picked multi-window stage keeps
// its own roles and only gets _setRequestedFrontmostEntity: 0x1c729693c), then EVERY entity of ctx.previousEntities that is not home/previous/empty and not already in
// ctx.entities goes into the first free role of {2,5,6,7,8,9} (block 0x1c76f2bb8 via 0x1c7296ed0), peek := none, mode := 3.  The unchanged main body (same in 16.0) builds the stage
// elements from [ctx entities], so roles 5+ become stage windows and the previous windows stay in the transaction's "to" set.  16.0 has no such branch: with chamois it runs the
// Split View peek merge (0x1c5e241fc..0x1c5e260e4) that can keep only the previous primary, and the supportsSplitView gate (0x1c5e24888) then collapses the pair to the picked app.
// The merge is done on the ctx BEFORE %orig; requestedPeekConfiguration = 1 during %orig makes 16.0 take its own "explicit none" path (0x1c5e2418c) and skip the legacy merge.
// Cases 1-3 of the 16.2 branch (request == previous stage, nothing real in the request, Home while peeking) are not merged here (the stock code runs unchanged for them).
// ---------------------------------------------------------------------------------------------------------------------------------------------------
static BOOL G3C_PeekValid(long long cfg) { return (cfg & ~1LL) == 2; }           // _SBPeekConfigurationIsValid (16.2 0x1c77229fc)
static BOOL G3C_Real(id e) { return e && ![e isEmptyWorkspaceEntity] && ![e isPreviousWorkspaceEntity]; }
static NSString *G3C_EntDesc(id e) { return e ? [NSString stringWithFormat:@"%@", e] : @"nil"; }
static BOOL G3C_EndPeekPick(id mgr, id ctx) {
    if (!ctx || !BP_OnName("g3c_endpeek") || !BP_OnName("g3c_addwin")) return NO;
    if (![ctx respondsToSelector:@selector(previousEntities)] || ![ctx respondsToSelector:@selector(setEntity:forLayoutRole:)]) return NO;
    id rq = [ctx request];
    if ([ctx isBackground] || (rq && [rq respondsToSelector:@selector(source)] && [rq source] == 0xe)) return NO;                 // 0x1c7295398 (background path)
    if (!G3C_Chamois(mgr, ctx)) return NO;
    id prev = [ctx previousLayoutState];
    if (!prev || !G3C_PeekValid([prev peekConfiguration]) || [ctx requestedPeekConfiguration] != 0) return NO;                   // 0x1c7295ffc..0x1c7296030
    NSSet *ents = [ctx entities], *pents = [ctx previousEntities];
    if (!pents.count || [ents isEqualToSet:pents]) return NO;                                                                     // case 1 (stock)
    id A = [ctx activatingEntity], E1 = [ctx entityForLayoutRole:1], E2 = [ctx entityForLayoutRole:2], E3 = [ctx entityForLayoutRole:3];
    if (!A && E1 && !E2 && !E3) { A = E1; E1 = nil; }                                                                             // 0x1c7295470
    if (!G3C_Real(E1) && !G3C_Real(A)) return NO;                                                                                 // case 2 (stock)
    if (A && [A isHomeScreenEntity]) return NO;                                                                                   // case 3 (stock)
    if (G3C_Real(A)) [ctx setEntity:A forLayoutRole:1];                                                                           // 0x1c7296d70
    else if (E1) [ctx _setRequestedFrontmostEntity:E1];                                                                           // 0x1c729693c
    NSArray *prevs = [[pents allObjects] sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {                              // deterministic (16.2 iterates the NSSet)
        long long x = [a layoutRole], y = [b layoutRole];
        return x < y ? NSOrderedAscending : (x > y ? NSOrderedDescending : NSOrderedSame);
    }];
    static const long long kRoles[] = { 1, 2, 5, 6, 7, 8, 9 };            // 162 enumeration order of _SBLayoutRoleEnumerateValidRoles filtered by _SBLayoutRoleIsValidForSplitView
    NSMutableString *placed = [NSMutableString string];
    for (id e in prevs) {
        if ([e isHomeScreenEntity] || [e isPreviousWorkspaceEntity] || [e isEmptyWorkspaceEntity]) continue;                     // 0x1c7296e1c..0x1c7296e38
        if ([[ctx entities] containsObject:e]) continue;                                                                          // 0x1c7296e40..0x1c7296e64
        for (size_t i = 0; i < sizeof kRoles / sizeof *kRoles; i++) {
            id cur = [ctx entityForLayoutRole:kRoles[i]];
            if (!cur || [cur isEmptyWorkspaceEntity]) { [ctx setEntity:e forLayoutRole:kRoles[i]]; [placed appendFormat:@" %lld:%@", kRoles[i], G3C_EntDesc(e)]; break; }
        }
    }
    if (BP_LogEnabled()) BP_Log(@"[g3c] endpeek: A=%@ E1=%@ previous entities %lu -> roles added:%@ (reqPeek 0 -> 1 for the stock body)", G3C_EntDesc(A), G3C_EntDesc(E1), (unsigned long)pents.count, placed);
    return YES;
}
// copy of a layout state with peek and mode forced (the stock result for a peek request equals the previous state apart from these two)
static id G3C_StateWith(id r, long long peek, long long mode) {
    if (![r respondsToSelector:@selector(_initWithLayoutState:)]) return r;
    id n = [[[r class] alloc] _initWithLayoutState:r];
    Ivar ip = class_getInstanceVariable([n class], "_peekConfiguration"), im = class_getInstanceVariable([n class], "_unlockedEnvironmentMode");
    if (!n || !ip || !im) return r;
    *(long long *)((uint8_t *)(__bridge void *)n + ivar_getOffset(ip)) = peek;
    *(long long *)((uint8_t *)(__bridge void *)n + ivar_getOffset(im)) = mode;
    return n;
}

%group G3C_Peek
%hook SBMainDisplayLayoutStateManager
- (id)_layoutStateForApplicationTransitionContext:(id)ctx {
    BOOL merged = G3C_EndPeekPick(self, ctx);
    long long savedReq = merged ? [ctx requestedPeekConfiguration] : 0;
    if (merged) [ctx setRequestedPeekConfiguration:1];
    id r = nil;
    @try {
        r = %orig;
    } @finally {
        if (merged) [ctx setRequestedPeekConfiguration:savedReq];
    }
    if (merged && r && ([r peekConfiguration] != 1 || [r unlockedEnvironmentMode] != 3)) {                                       // 16.2 0x1c7296f40: mode 3, peek none
        if (BP_LogEnabled()) BP_Log(@"[g3c] endpeek: stock result had mode %lld peek %lld -> 16.2 mode 3 peek 1", [r unlockedEnvironmentMode], [r peekConfiguration]);
        r = G3C_StateWith(r, 1, 3);
    }
    if (merged) {
        if (BP_LogEnabled()) BP_Log(@"[g3c] endpeek: result %@", r);
        return r;
    }
    if (!r || !ctx || !BP_OnName("g3c_addwin") || ![ctx respondsToSelector:@selector(requestedPeekConfiguration)]) return r;
    long long req = [ctx requestedPeekConfiguration];
    if (!G3C_PeekValid(req)) return r;
    if (!G3C_Chamois(self, ctx)) return r;
    id prev = [ctx respondsToSelector:@selector(previousLayoutState)] ? [ctx previousLayoutState] : nil;
    if (!prev || G3C_PeekValid([prev peekConfiguration])) return r;                // only the START of a peek (16.2 0x1c7296014)
    long long mode = 1;
    if (BP_OnName("g3c_peekmode")) {
        id recents = [self respondsToSelector:@selector(_recentAppLayouts)] ? [self _recentAppLayouts] : nil;
        id list = [recents respondsToSelector:@selector(recentsIncludingHiddenAppLayouts:)] ? [recents recentsIncludingHiddenAppLayouts:NO] : nil;
        mode = ([list respondsToSelector:@selector(count)] && [(NSArray *)list count] >= 2) ? 2 : 1;
    } else mode = [r unlockedEnvironmentMode];
    long long haveMode = [r unlockedEnvironmentMode], havePeek = [r peekConfiguration];
    if (havePeek == req && haveMode == mode) return r;
    id n = G3C_StateWith(r, req, mode);
    if (n == r) return r;
    BP_Log(@"[g3c] add window: stock layout state kept mode %lld peek %lld (previous stage elements %lu) -> 16.2 mode %lld peek %lld", haveMode, havePeek,
           (unsigned long)[(NSArray *)[(id)prev valueForKey:@"elements"] count], mode, req);
    return n;
}
%end
%end // G3C_Peek

void G3C_Setup(void) {
    %init(G3C_Zoom);
    %init(G3C_Peek);
}
