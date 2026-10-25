// P1VC.m : the remaining unported SBFluidSwitcherViewController / item container / footer / layer methods of REVIEW-CORE-0.7.9 section 2.1 (specs/CORE-LEFTOVERS-0.7.9.md item 2).
// 16.0 = 20A8372, 16.2 = 20C65 (unslid cache addresses). Every body below was decoded from the 16.2 disassembly and diffed against the 16.0 method (addresses in the comments).
// Switches (all default on, the replaced IMP checks them at call time and runs the saved 16.0 IMP when off): p1_vckeys (performKeyboardShortcutAction:), p1_kbsuppress (M2),
// p1_vcmisc (the small VC methods), p1_container (item container / footer / layer). Logs: grep "p1vc:" in Backport162.log.

#import "G1BKit.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wunused-variable"
#pragma clang diagnostic ignored "-Wundeclared-selector"


extern void P1_NoteMissing(id o, SEL x);
extern Ivar P1_IvarOf(id o, const char *name);
static inline BOOL PV_Resp(id o, SEL x) {
    if (!o) return NO;
    if ([o respondsToSelector:x]) return YES;
    P1_NoteMissing(o, x);
    return NO;
}
static BOOL PV_On(const char *n) { return BP_OnName("p1_vc") && BP_OnName(n); }

static id PV_S0(id o, const char *s) { SEL x = sel_registerName(s); return PV_Resp(o, x) ? ((id (*)(id, SEL))objc_msgSend)(o, x) : nil; }
static id PV_S1(id o, const char *s, id a) { SEL x = sel_registerName(s); return PV_Resp(o, x) ? ((id (*)(id, SEL, id))objc_msgSend)(o, x, a) : nil; }
static BOOL PV_B0(id o, const char *s) { SEL x = sel_registerName(s); return PV_Resp(o, x) ? ((BOOL (*)(id, SEL))objc_msgSend)(o, x) : NO; }
static long long PV_L0(id o, const char *s) { SEL x = sel_registerName(s); return PV_Resp(o, x) ? ((long long (*)(id, SEL))objc_msgSend)(o, x) : 0; }
static double PV_D0(id o, const char *s) { SEL x = sel_registerName(s); return PV_Resp(o, x) ? ((double (*)(id, SEL))objc_msgSend)(o, x) : 0.0; }
static void PV_V0(id o, const char *s) { SEL x = sel_registerName(s); if (PV_Resp(o, x)) ((void (*)(id, SEL))objc_msgSend)(o, x); }
static void PV_V1(id o, const char *s, id a) { SEL x = sel_registerName(s); if (PV_Resp(o, x)) ((void (*)(id, SEL, id))objc_msgSend)(o, x, a); }
static void PV_VB(id o, const char *s, BOOL a) { SEL x = sel_registerName(s); if (PV_Resp(o, x)) ((void (*)(id, SEL, BOOL))objc_msgSend)(o, x, a); }
static id PV_Ivar(id o, const char *name) {
    Ivar iv = P1_IvarOf(o, name);
    return BP_ObjIvar(o, iv);
}
static void PV_SetIvar(id o, const char *name, id v) {
    Ivar iv = P1_IvarOf(o, name);
    if (iv) BP_SetObjIvar(o, iv, v);
}
static unsigned long long PV_IvarULL(id o, const char *name) {
    Ivar iv = P1_IvarOf(o, name);
    return iv ? *(unsigned long long *)((uint8_t *)(__bridge void *)o + ivar_getOffset(iv)) : 0;
}
static BOOL PV_IvarB(id o, const char *name) {
    Ivar iv = P1_IvarOf(o, name);
    return iv ? *(BOOL *)((uint8_t *)(__bridge void *)o + ivar_getOffset(iv)) : NO;
}
static IMP PV_Replace(const char *cls, const char *sel, IMP imp) {
    Class c = NSClassFromString([NSString stringWithUTF8String:cls]);
    SEL s = sel_registerName(sel);
    Method m = c ? class_getInstanceMethod(c, s) : NULL;
    if (!m) { BP_Log(@"p1vc: %s -%s not found, not replaced", cls, sel); return NULL; }
    IMP prev = method_getImplementation(m);
    class_replaceMethod(c, s, imp, method_getTypeEncoding(m));
    return prev;
}

static IMP sKeys, sKbAcquire, sIconVis, sHomePtr, sLeaf, sDockLevel, sPlus, sOverlayFrame;
static IMP sCoder, sFocus, sFooterTap, sSubtitle, sLayerTransform, sMatchMove;

// ---------------------------------------------------------------------------------------------- performKeyboardShortcutAction: (16.2 0x1c743ace4, 377 -> 223 insns; 16.0 0x1c5fc2070)
// 16.2 jump table (decoded, actions 3..20): 3 App Expose of the keyboard focused app (bundleIDShowingAppExpose toggle, request source 0x33), 4 / 5 next / previous window of the focused app
// (_navigate...InForwardDirection:matchFocusedApp:), 6 toggle the floating app, 15 / 16 next / previous window of any app, 7 8 11 12 13 14 17 18 19 20 the live content overlay coordinator's
// -performSwitcherKeyboardShortcutAction:, 9 / 10 and everything else nothing. 16.0 additionally handled 21 / 22 inline with the identifier based cycling code; 16.2 has no such action, the saved
// 16.0 body still serves them (a 16.2 caller never sends them).
static void PV_Navigate(id vc, BOOL forward, BOOL matchFocusedApp) {
    SEL n162 = sel_registerName("_navigateFromFocusedAppWindowSceneToNextSceneInForwardDirection:matchFocusedApp:");
    SEL n160 = sel_registerName("_navigateFromFocusedAppWindowSceneToNextScene:matchFocusedApp:");
    SEL s = [vc respondsToSelector:n162] ? n162 : n160;
    if ([vc respondsToSelector:s]) ((void (*)(id, SEL, BOOL, BOOL))objc_msgSend)(vc, s, forward, matchFocusedApp);
}
static void PV_AppExpose(id vc, long long action) {
    id coordinator = PV_Ivar(vc, "_liveContentOverlayCoordinator");
    id focused = PV_S0(coordinator, "appLayoutForKeyboardFocusedScene");
    if (!focused) return;
    id bundleID = PV_S0(PV_S0(PV_S0(focused, "allItems"), "firstObject"), "bundleIdentifier");
    __block BOOL found = NO;
    id shelves = PV_Ivar(vc, "_visibleShelves");
    for (id key in [PV_S0(shelves, "allKeys") isKindOfClass:[NSArray class]] ? PV_S0(shelves, "allKeys") : @[]) {       // block 0x1c743b060 (same as 16.0)
        if (![PV_S0(key, "bundleIdentifier") isEqualToString:bundleID]) continue;
        id shelf = [shelves objectForKey:key];
        SEL pk = sel_registerName("performKeyboardShortcutAction:");
        if ([shelf respondsToSelector:pk]) ((void (*)(id, SEL, long long))objc_msgSend)(shelf, pk, action);
        found = YES;
        break;
    }
    if (found) return;
    id shown = PV_S0(PV_S0(PV_S0(vc, "layoutContext"), "layoutState"), "bundleIDShowingAppExpose");
    if (shown && [bundleID isEqualToString:shown]) bundleID = nil;                // 16.2 only: the same app again closes App Expose (request without a bundle identifier)
    id workspace = PV_S0((id)NSClassFromString(@"SBWorkspace"), "mainWorkspace");
    id config = PV_S0(vc, "_fbsDisplayConfiguration");
    void (^builder)(id) = ^(id request) {                                         // block 0x1c743b108 / 0x1c743b1a8
        SEL ss = sel_registerName("setSource:");
        if ([request respondsToSelector:ss]) ((void (*)(id, SEL, long long))objc_msgSend)(request, ss, 0x33);
        void (^mod)(id) = ^(id ctx) {
            PV_V1(ctx, "setRequestedAppExposeBundleID:", bundleID);
            SEL sm = sel_registerName("setRequestedUnlockedEnvironmentMode:");
            if ([ctx respondsToSelector:sm]) ((void (*)(id, SEL, long long))objc_msgSend)(ctx, sm, 3);
        };
        PV_V1(request, "modifyApplicationContext:", mod);
    };
    SEL rt = sel_registerName("requestTransitionWithOptions:displayConfiguration:builder:");
    if ([workspace respondsToSelector:rt]) ((id (*)(id, SEL, unsigned long long, id, id))objc_msgSend)(workspace, rt, 0, config, builder);
}
static void PV_Keys(id self, SEL _cmd, long long action) {
    if (!PV_On("p1_vckeys")) { ((void (*)(id, SEL, long long))sKeys)(self, _cmd, action); return; }
    switch (action) {
        case 3: PV_AppExpose(self, action); return;
        case 4: case 5: PV_Navigate(self, action == 4, YES); return;
        case 6: PV_V0(self, "_toggleFloatingAppVisibility"); return;
        case 15: case 16: PV_Navigate(self, action == 15, NO); return;
        case 7: case 8: case 11: case 12: case 13: case 14: case 17: case 18: case 19: case 20: {
            id c = PV_Ivar(self, "_liveContentOverlayCoordinator");
            SEL s = sel_registerName("performSwitcherKeyboardShortcutAction:");
            if ([c respondsToSelector:s]) ((void (*)(id, SEL, long long))objc_msgSend)(c, s, action);
            return;
        }
        case 9: case 10: return;
        case 21: case 22: ((void (*)(id, SEL, long long))sKeys)(self, _cmd, action); return;   // 16.0 only (see above)
        default: return;
    }
}

// ---------------------------------------------------------------------------------------------- M2 _acquireKeyboardSuppressionAssertionForMode: (16.2 0x1c7459e50; 16.0 0x1c5fe088c)
// 16.2 asks the VC's OWN window scene's hosted keyboard window controller (16.0: the main display scene manager's flag) and starts the suppression with
// startSuppressingKeyboardWithReason:predicate:displayIdentity: with a NIL identity (= every display, the same reach as the 16.0 call; X7Keyboard.x provides the 3 argument method).
static BOOL PV_UsingMedusaKeyboard(id vc) {
    id ws = PV_S0(vc, "_sbWindowScene");
    id ctl = PV_S0(ws, "medusaHostedKeyboardWindowController");                  // 16.2 SBWindowScene accessor (G3B keeps the controllers as associated objects of the scene)
    if (ctl) return PV_B0(ctl, "isUsingMedusaHostedKeyboardWindow");
    id sm = PV_S0(ws, "sceneManager");
    if ([sm respondsToSelector:sel_registerName("_isUsingMedusaHostedKeyboardWindow")]) return PV_B0(sm, "_isUsingMedusaHostedKeyboardWindow");
    return PV_B0(PV_S0((id)NSClassFromString(@"SBSceneManagerCoordinator"), "mainDisplaySceneManager"), "_isUsingMedusaHostedKeyboardWindow");      // the 16.0 query
}
static void PV_KbAcquire(id self, SEL _cmd, id mode) {
    if (!PV_On("p1_kbsuppress")) { ((void (*)(id, SEL, id))sKbAcquire)(self, _cmd, mode); return; }
    Class mc = NSClassFromString(@"SBSwitcherKeyboardSuppressionMode");
    id none = PV_S0((id)mc, "suppressionModeNone");
    if (mode == none) { BP_Log(@"p1vc: _acquireKeyboardSuppressionAssertionForMode: called with the None mode (16.2 asserts: We shouldn't be acquiring a keyboard suppression if the mode is None.)"); return; }
    BOOL medusa = PV_UsingMedusaKeyboard(self);
    id lc = PV_S0(self, "layoutContext");
    id elems = PV_S0(PV_S0(lc, "layoutState"), "elements");
    BOOL apply = [elems respondsToSelector:@selector(count)] && [elems count] > 1;
    if (!apply) {
        id from = PV_S0(PV_S0(lc, "transitioningFromLayoutState"), "elements");
        BOOL fromMany = [from respondsToSelector:@selector(count)] && [from count] > 1;
        apply = fromMany || medusa || PV_B0(mode, "applyAssertionEvenIfAppIsHostingTheKeyboard");
    }
    if (!apply) return;
    id predicate = nil;
    if (PV_B0(mode, "suppressesSwitcherScenesOnly")) {
        SEL ps = sel_registerName("_sceneDeactivationPredicateMatchingAppLayouts:");
        if ([self respondsToSelector:ps]) predicate = ((id (*)(id, SEL, id))objc_msgSend)(self, ps, PV_S0(mode, "appLayouts"));
    }
    id mgr = PV_S0((id)NSClassFromString(@"SBKeyboardSuppressionManager"), "sharedInstance");
    id reason = PV_Ivar(self, "_fluidSwitcherAssertionReason");
    SEL three = sel_registerName("startSuppressingKeyboardWithReason:predicate:displayIdentity:"), two = sel_registerName("startSuppressingKeyboardWithReason:predicate:");
    if ([mgr respondsToSelector:three]) ((void (*)(id, SEL, id, id, id))objc_msgSend)(mgr, three, reason, predicate, nil);
    else if ([mgr respondsToSelector:two]) ((void (*)(id, SEL, id, id))objc_msgSend)(mgr, two, reason, predicate);
}

// ---------------------------------------------------------------------------------------------- _performModifierIconViewVisibilityUpdateResponse: (16.2 0x1c745cd90, 281 -> 240; 16.0 0x1c5fe35dc)
// 16.0 ends with a second sb_animateWithSettings (setAllIconElementsButLabelHidden:NO) when SBIconLocationGroupContainsLocation && isChamoisWindowingUIEnabled &&
// !_isPerformingMatchMoveToIconView; 16.2 dropped that tail. The 16.0 body is kept and the match move test (its only use of that query) answers YES for its extent.
static __thread __unsafe_unretained id tNoTail;
static void PV_IconVis(id self, SEL _cmd, id response) {
    if (!PV_On("p1_vcmisc")) { ((void (*)(id, SEL, id))sIconVis)(self, _cmd, response); return; }
    id save = tNoTail; tNoTail = self;
    ((void (*)(id, SEL, id))sIconVis)(self, _cmd, response);
    tNoTail = save;
}
static BOOL PV_MatchMove(id self, SEL _cmd) {
    if (tNoTail == self) return YES;
    return ((BOOL (*)(id, SEL))sMatchMove)(self, _cmd);
}

// ---------------------------------------------------------------------------------------------- small VC methods
// _updateHomeScreenPointerInteractions 16.2 0x1c74583f4: the data source is told only when [self _controlsHomeScreenContents] (the review had it the other way round)
static void PV_HomePointer(id self, SEL _cmd) {
    if (!PV_On("p1_vcmisc")) { ((void (*)(id, SEL))sHomePtr)(self, _cmd); return; }
    id d = PV_S0(self, "delegate");
    if (!PV_B0(self, "_controlsHomeScreenContents")) return;
    SEL s = sel_registerName("switcherContentController:setPointerInteractionsEnabled:");
    if ([d respondsToSelector:s]) ((void (*)(id, SEL, id, BOOL))objc_msgSend)(d, s, self, PV_B0(PV_Ivar(self, "_rootModifier"), "wantsHomeScreenPointerInteractions"));
}
// _leafAppLayoutInLiveContentOverlaysWithLayoutRole: 16.2 0x1c7439f84: a leaf without an adjusted layout is matched through the controller's current app layout
static id PV_LeafInOverlays(id self, SEL _cmd, long long role) {
    if (!PV_On("p1_vcmisc")) return ((id (*)(id, SEL, long long))sLeaf)(self, _cmd, role);
    NSDictionary *overlays = PV_Ivar(self, "_liveContentOverlays");
    if (![overlays isKindOfClass:[NSDictionary class]]) return nil;
    if ([overlays count] == 1) return [[overlays allKeys] firstObject];
    NSDictionary *adjustedMap = PV_Ivar(self, "_leafAppLayoutsToAdjustedAppLayouts");
    SEL lfr = sel_registerName("leafAppLayoutForRole:");
    for (id key in [overlays allKeys]) {
        id adjusted = [adjustedMap objectForKey:key];
        id candidate = adjusted;
        if (!candidate) candidate = PV_S0(PV_S0(PV_S0(self, "switcherController"), "layoutState"), "appLayout");
        id leaf = [candidate respondsToSelector:lfr] ? ((id (*)(id, SEL, long long))objc_msgSend)(candidate, lfr, role) : nil;
        if (leaf == key) return key;
    }
    return nil;
}
// _updateFloatingDockWindowLevelAssertion 16.2 0x1c745a234: the in-app-over-folder assertion no longer cancels the window level assertion
static void PV_DockLevel(id self, SEL _cmd) {
    if (!PV_On("p1_vcmisc")) { ((void (*)(id, SEL))sDockLevel)(self, _cmd); return; }
    id root = PV_Ivar(self, "_rootModifier");
    if (!PV_B0(root, "wantsDockWindowLevelAssertion")) {
        PV_V0(PV_Ivar(self, "_switcherFloatingDockWindowLevelAssertion"), "invalidate");
        PV_SetIvar(self, "_switcherFloatingDockWindowLevelAssertion", nil);
        return;
    }
    long long priority = PV_L0(root, "dockWindowLevelPriority");
    double level = PV_D0(root, "dockWindowLevel");
    id old = PV_Ivar(self, "_switcherFloatingDockWindowLevelAssertion");
    if (old && PV_L0(old, "priority") == priority && PV_D0(old, "level") == level) return;
    Class ac = NSClassFromString(@"SBFloatingDockWindowLevelAssertion");
    SEL ini = sel_registerName("initWithFloatingDockController:priority:level:reason:");
    if (![ac instancesRespondToSelector:ini]) { ((void (*)(id, SEL))sDockLevel)(self, _cmd); return; }
    id fresh = G1B_INIT(id, long long, double, id)([ac alloc], ini, PV_S0(self, "_floatingDockController"), priority, level, NSStringFromClass([self class]));
    PV_SetIvar(self, "_switcherFloatingDockWindowLevelAssertion", fresh);
    PV_V0(old, "invalidate");
}
// _updatePlusButtonPresence 16.2 0x1c74575b8 (16.0 0x1c5fde30c): no plus button for com.apple.InCallService; symbol weight 6 and the image is tinted black (always original) instead of the button's tintColor
static void PV_Plus(id self, SEL _cmd) {
    if (!PV_On("p1_vcmisc")) { ((void (*)(id, SEL))sPlus)(self, _cmd); return; }
    id bundle = PV_S0(PV_Ivar(self, "_rootModifier"), "appExposeAccessoryButtonsBundleIdentifier");
    id button = PV_Ivar(self, "_plusButton");
    if (!bundle || [bundle isEqualToString:@"com.apple.InCallService"]) {
        if (button) { PV_V0(button, "removeFromSuperview"); PV_SetIvar(self, "_plusButton", nil); }
        return;
    }
    if (button) return;
    Class cfgC = NSClassFromString(@"UIImageSymbolConfiguration");
    SEL cfgS = sel_registerName("configurationWithPointSize:weight:");
    id image = PV_S1((id)NSClassFromString(@"UIImage"), "systemImageNamed:", @"plus");
    id cfg = [cfgC respondsToSelector:cfgS] ? ((id (*)(id, SEL, double, long long))objc_msgSend)((id)cfgC, cfgS, 14.1, 6) : nil;
    image = PV_S1(image, "imageWithConfiguration:", cfg);
    SEL tintS = sel_registerName("imageWithTintColor:renderingMode:");
    if ([image respondsToSelector:tintS]) image = ((id (*)(id, SEL, id, long long))objc_msgSend)(image, tintS, PV_S0((id)NSClassFromString(@"UIColor"), "blackColor"), 1);
    Class bc = NSClassFromString(@"SBFluidSwitcherButton");
    id b = G1B_INIT(CGRect)([bc alloc], sel_registerName("initWithFrame:"), CGRectZero);
    PV_SetIvar(self, "_plusButton", b);
    SEL setAlpha = sel_registerName("setAlpha:");
    if ([b respondsToSelector:setAlpha]) ((void (*)(id, SEL, double))objc_msgSend)(b, setAlpha, 0.0);
    PV_V1(b, "setBackdropGroupName:", @"AppExposeAccessoryButtonsMaterialGroupName");
    PV_V1(b, "setImage:", image);
    PV_V1(b, "setAccessibilityIdentifier:", @"switcher-plus-button");
    SEL ata = sel_registerName("addTarget:action:forControlEvents:");
    if ([b respondsToSelector:ata]) ((void (*)(id, SEL, id, SEL, unsigned long long))objc_msgSend)(b, ata, self, sel_registerName("_handlePlusButtonTapped:"), 0x40);
    PV_V1(PV_Ivar(self, "_contentView"), "addSubview:", b);
    PV_V0(PV_S0(self, "view"), "setNeedsLayout");
}
// overlayAccessoryViewFrameForIconOverlayView:fullPresented: 16.2 0x1c7451420: without an adjusted layout the container view bounds size is used (16.0: a size from the interface orientation)
static CGRect PV_OverlayFrame(id self, SEL _cmd, id view, BOOL fullPresented) {
    SEL cvb = sel_registerName("containerViewBounds");
    if (!PV_On("p1_vcmisc") || ![self respondsToSelector:cvb]) return ((CGRect (*)(id, SEL, id, BOOL))sOverlayFrame)(self, _cmd, view, fullPresented);
    if (!fullPresented) { SEL b = sel_registerName("bounds"); return [view respondsToSelector:b] ? ((CGRect (*)(id, SEL))objc_msgSend)(view, b) : CGRectZero; }
    id accessories = PV_Ivar(self, "_visibleOverlayAccessoryViews");
    id layout = [[PV_S1(accessories, "allKeysForObject:", view) isKindOfClass:[NSArray class]] ? PV_S1(accessories, "allKeysForObject:", view) : @[] firstObject];
    id leaf = PV_S0(layout, "anyLeafAppLayout");
    id adjusted = [PV_Ivar(self, "_leafAppLayoutsToAdjustedAppLayouts") objectForKey:leaf];
    CGRect cb = ((CGRect (*)(id, SEL))objc_msgSend)(self, cvb);
    CGSize size = cb.size;
    if (adjusted) {
        NSUInteger idx = [[PV_S0(self, "appLayouts") isKindOfClass:[NSArray class]] ? PV_S0(self, "appLayouts") : @[] indexOfObject:adjusted];
        id root = PV_Ivar(self, "_rootModifier");
        SEL ffi = sel_registerName("frameForIndex:"), pfi = sel_registerName("fullyPresentedFrameForIndex:frame:");
        CGRect frame = [root respondsToSelector:ffi] ? ((CGRect (*)(id, SEL, unsigned long long))objc_msgSend)(root, ffi, idx) : CGRectZero;
        CGRect full = [root respondsToSelector:pfi] ? ((CGRect (*)(id, SEL, unsigned long long, CGRect))objc_msgSend)(root, pfi, idx, frame) : CGRectZero;
        size = full.size;
    }
    return CGRectMake(0, 0, size.width, size.height);                            // _SBRectWithSize
}

// ---------------------------------------------------------------------------------------------- item container
// initWithCoder: 16.2 0x1c75e101c: asserts ("Override initWithFrame:delegate: instead"), then the designated init with zero arguments incl. a nil window scene (16.0: no window scene argument)
static __attribute__((ns_returns_retained)) id PV_Coder(__attribute__((ns_consumed)) id self, SEL _cmd, id coder) {
    SEL d = sel_registerName("initWithFrame:appLayout:delegate:active:windowScene:");
    if (!PV_On("p1_container") || ![self respondsToSelector:d]) return ((__attribute__((ns_returns_retained)) id (*)(__attribute__((ns_consumed)) id, SEL, id))sCoder)(self, _cmd, coder);
    BP_Log(@"p1vc: SBFluidSwitcherItemContainer initWithCoder: (16.2 asserts: Override initWithFrame:delegate: instead)");
    return ((__attribute__((ns_returns_retained)) id (*)(__attribute__((ns_consumed)) id, SEL, CGRect, id, id, BOOL, id))objc_msgSend)(self, d, CGRectZero, nil, nil, NO, nil);
}
// didUpdateFocusInContext:withAnimationCoordinator: 16.2 0x1c75e2f2c: the return key recognizer lists the Select press type instead of the private _setButtonType:4
static void PV_Focus(id self, SEL _cmd, id context, id coordinator) {
    if (!PV_On("p1_container")) { ((void (*)(id, SEL, id, id))sFocus)(self, _cmd, context, coordinator); return; }
    id d = PV_S0(self, "delegate");
    SEL cdf = sel_registerName("container:didBecomeFocused:");
    if (PV_S0(context, "nextFocusedItem") == self) {
        if ([d respondsToSelector:cdf]) ((void (*)(id, SEL, id, BOOL))objc_msgSend)(d, cdf, self, YES);
        Class tc = NSClassFromString(@"UITapGestureRecognizer");
        id r = G1B_INIT(id, SEL)([tc alloc], sel_registerName("initWithTarget:action:"), self, sel_registerName("_returnKeyPressed:"));
        PV_SetIvar(self, "_returnKeyGestureRecognizer", r);
        PV_V1(r, "setAllowedPressTypes:", @[ @4 ]);                              // UIPressTypeSelect
        PV_V1(self, "addGestureRecognizer:", r);
    } else if (PV_S0(context, "previouslyFocusedItem") == self) {
        if ([d respondsToSelector:cdf]) ((void (*)(id, SEL, id, BOOL))objc_msgSend)(d, cdf, self, NO);
        PV_V1(self, "removeGestureRecognizer:", PV_Ivar(self, "_returnKeyGestureRecognizer"));
        PV_SetIvar(self, "_returnKeyGestureRecognizer", nil);
    }
}
// SBFluidSwitcherItemContainerLayer -setTransform: 16.2 0x1c75e5304: the same transform is not set again (16.0 always called super; the review's "mirrors to the page view" is not what the disassembly does)
typedef struct { double m[16]; } PVT3D;
static void PV_LayerTransform(id self, SEL _cmd, PVT3D t) {
    if (PV_On("p1_container")) {
        SEL tr = sel_registerName("transform");
        if ([self respondsToSelector:tr]) {
            PVT3D cur = ((PVT3D (*)(id, SEL))objc_msgSend)(self, tr);
            static BOOL (*feq)(double, double); static dispatch_once_t once;
            dispatch_once(&once, ^{ feq = (BOOL (*)(double, double))dlsym(RTLD_DEFAULT, "BSFloatEqualToFloat"); });
            BOOL equal = YES;
            for (int i = 0; i < 16 && equal; i++) equal = feq ? feq(cur.m[i], t.m[i]) : cur.m[i] == t.m[i];
            if (equal) return;
        }
    }
    ((void (*)(id, SEL, PVT3D))sLayerTransform)(self, _cmd, t);
}

// ---------------------------------------------------------------------------------------------- footer view
// _handleTapGestureRecognizer: 16.2 0x1c7587b90 (16.0 0x1c6102688 hit tested frames inset by switcherShelfSplitViewIconInset): footer style != 0 hit tests the icon views with
// convertPoint:fromView: / pointInside:withEvent:, style 0 divides the width evenly (mirrored for right-to-left)
static void PV_FooterTap(id self, SEL _cmd, id tap) {
    if (!PV_On("p1_container")) { ((void (*)(id, SEL, id))sFooterTap)(self, _cmd, tap); return; }
    unsigned long long style = PV_IvarULL(self, "_footerStyle");
    SEL liv = sel_registerName("locationInView:");
    CGPoint loc = [tap respondsToSelector:liv] ? ((CGPoint (*)(id, SEL, id))objc_msgSend)(tap, liv, self) : CGPointZero;
    NSArray *items = PV_Ivar(self, "_visibleTitleItems");
    NSArray *iconViews = PV_Ivar(self, "_iconViews");
    id item = nil;
    if (style != 0) {
        for (NSUInteger i = 0; i < items.count && i < iconViews.count; i++) {
            id iv = iconViews[i];
            SEL cp = sel_registerName("convertPoint:fromView:"), pi = sel_registerName("pointInside:withEvent:");
            CGPoint p = [iv respondsToSelector:cp] ? ((CGPoint (*)(id, SEL, CGPoint, id))objc_msgSend)(iv, cp, loc, self) : loc;
            if ([iv respondsToSelector:pi] && ((BOOL (*)(id, SEL, CGPoint, id))objc_msgSend)(iv, pi, p, nil)) { item = items[i]; break; }
        }
    } else {
        SEL bs = sel_registerName("bounds");
        double width = [self respondsToSelector:bs] ? ((CGRect (*)(id, SEL))objc_msgSend)(self, bs).size.width : 0;
        long long n = (long long)items.count, idx = n ? (long long)(loc.x / (width / (double)n)) : -1;
        if ([(id)[UIApplication sharedApplication] respondsToSelector:sel_registerName("userInterfaceLayoutDirection")] && PV_L0((id)[UIApplication sharedApplication], "userInterfaceLayoutDirection") == 1) idx = n - 1 - idx;
        if (idx < 0 || idx >= n) return;
        item = items[idx];
    }
    if (!item) return;
    id delegate = PV_S0(self, "delegate") ?: PV_Ivar(self, "_delegate");
    SEL ds = sel_registerName("itemContainerFooterView:didSelectTitleItem:");
    if ([delegate respondsToSelector:ds]) ((void (*)(id, SEL, id, id))objc_msgSend)(delegate, ds, self, item);
}
// _makeSubtitleLabel 16.2 0x1c7587ff4: the label is user interaction enabled
static id PV_Subtitle(id self, SEL _cmd) {
    id label = ((id (*)(id, SEL))sSubtitle)(self, _cmd);
    if (PV_On("p1_container")) PV_VB(label, "setUserInteractionEnabled:", YES);
    return label;
}

void P1VC_Setup(void) {
    const char *V = "SBFluidSwitcherViewController", *I = "SBFluidSwitcherItemContainer", *F = "SBFluidSwitcherItemContainerFooterView", *L = "SBFluidSwitcherItemContainerLayer";
    sKeys = PV_Replace(V, "performKeyboardShortcutAction:", (IMP)PV_Keys);
    sKbAcquire = PV_Replace(V, "_acquireKeyboardSuppressionAssertionForMode:", (IMP)PV_KbAcquire);
    sIconVis = PV_Replace(V, "_performModifierIconViewVisibilityUpdateResponse:", (IMP)PV_IconVis);
    sMatchMove = PV_Replace(V, "_isPerformingMatchMoveToIconView", (IMP)PV_MatchMove);
    sHomePtr = PV_Replace(V, "_updateHomeScreenPointerInteractions", (IMP)PV_HomePointer);
    sLeaf = PV_Replace(V, "_leafAppLayoutInLiveContentOverlaysWithLayoutRole:", (IMP)PV_LeafInOverlays);
    sDockLevel = PV_Replace(V, "_updateFloatingDockWindowLevelAssertion", (IMP)PV_DockLevel);
    sPlus = PV_Replace(V, "_updatePlusButtonPresence", (IMP)PV_Plus);
    sOverlayFrame = PV_Replace(V, "overlayAccessoryViewFrameForIconOverlayView:fullPresented:", (IMP)PV_OverlayFrame);
    sCoder = PV_Replace(I, "initWithCoder:", (IMP)PV_Coder);
    sFocus = PV_Replace(I, "didUpdateFocusInContext:withAnimationCoordinator:", (IMP)PV_Focus);
    sFooterTap = PV_Replace(F, "_handleTapGestureRecognizer:", (IMP)PV_FooterTap);
    sSubtitle = PV_Replace(F, "_makeSubtitleLabel", (IMP)PV_Subtitle);
    sLayerTransform = PV_Replace(L, "setTransform:", (IMP)PV_LayerTransform);
    BP_Log(@"p1vc: installed");
}

#pragma clang diagnostic pop
