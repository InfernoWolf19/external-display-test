// Y24Drag.x : delta sweep pass 3, drag and drop (F3).  Setup: constructor.  Log prefix "[y24]".
//
//  y24_droptrack  +[SBDragAndDropWorkspaceTransaction _shouldTrackLocationOfDropSession:forSwitcherController:isCurrentlyTracking:]  16.2 0x1c770691c (16.0 0x1c626e7a8, a class method).
//                 Whole 16.2 body re-implemented (it replaces the 16.0 one; the three decoded differences are inside the same decision tree, so the tree is rebuilt, not post filtered):
//                 (1) 16.2 first rejects a point outside UIRectInset(view bounds, .5, .5, .5, .5) of the switcher view (0x1c7706b80..b b0): 16.0 had no such test.  The point is the
//                     location of the drag session in the switcher view (d11/d10); the banner test uses the same point converted to the screen's fixed coordinate space (d12/d13, 0x1c7706a80).
//                 (2) Stage Manager (chamois): the strip hit area (a strip wide band at the leading edge of the view, stripWidth of [vc chamoisLayoutAttributes], mirrored for RTL) counts only while
//                     [vc _areContinuousExposeStripsUnoccluded] (0x1c7706bc4, else the strip hit is NO: 16.0 always computed it, from rootSettings chamoisSettings
//                     layoutAttributesForWindowScene:requiresFullScreen: which gives the same stripWidth).
//                 (3) dropZones == 1 under Stage Manager (content drag): [vc _itemContainerAtLocation:environment:0] must be nil (then the result is !strip, like 16.0) or its size must equal the
//                     size of the view (0x1c7706c68..c9c); in that second case the chain of the non Stage Manager content drag runs (full screen region / side gutter block / floating gutter,
//                     layout role scan with multitaskingDragExclusionRects), which 16.0 never ran under Stage Manager (it returned NO for any container under the finger).  Any other container: NO.
//                 Everything else is the 16.0 sequence, verified instruction by instruction (blocks 0x1c7707248 = 16.0 0x1c626f0b0 and 0x1c77072f8 = 0x1c626f160, identical but for the address of the
//                 role constant 3, SBLayoutRoleFloating, both builds hold 3).  The role scan order is that of _SBLayoutRoleEnumerateValidRoles (1, 2, 4..9, then 3).
//                 The helpers are the 16.0 class methods (all present in both builds): isDragOverFullscreenRegionAtLocation:inBounds:, screenEdgeForDragOverSideGutterRegionsAtLocation:inBounds:
//                 totalContentDragGutterWidth:screenInsets:, _screenInsetsForUIDragDropSession:, sourceSceneInterfaceOrientedBoundsForDropSession:switcherController:, prototypeSettings*Width.
//                 The banner UTI is the exported global NCUserNotificationDragPrivateTypeIdentifier (UserNotificationsUIKit; same slot kind in both builds), the drag item test is the exported
//                 C function SBApplicationDropSessionGetDragItem (16.0 0x1c635f1b8, 16.2 0x1c7804b8c).
//                 When a required symbol / selector is missing the method is NOT replaced (logged once at setup, GUARD) so the 16.0 body keeps running.
// Needs a device: with Stage Manager on, drag a file / link over a full screen app and over the strip: the drop target highlight appears only inside the view; with the strips hidden
// behind a window the leading edge no longer counts as the strip.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import "Y17Common.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

static IMP gY24OrigTrack;

// ---- typed sends (a missing selector is logged once through Y17_GuardOnce and answers 0 / nil / CGRectZero, but the setup refuses to install when one of them is absent) ----
static BOOL Y24_Has(id o, const char *sel) {
    if (o && [o respondsToSelector:sel_registerName(sel)]) return YES;
    Y17_GuardOnce("droptrack", o, sel);
    return NO;
}
static CGRect Y24_Rect0(id o, const char *sel) { return Y24_Has(o, sel) ? ((CGRect (*)(id, SEL))objc_msgSend)(o, sel_registerName(sel)) : CGRectZero; }
static long long Y24_LL0(id o, const char *sel) { return Y24_Has(o, sel) ? ((long long (*)(id, SEL))objc_msgSend)(o, sel_registerName(sel)) : 0; }
static double Y24_D0(id o, const char *sel) { return Y24_Has(o, sel) ? ((double (*)(id, SEL))objc_msgSend)(o, sel_registerName(sel)) : 0; }
static BOOL Y24_B0(id o, const char *sel) { return Y24_Has(o, sel) ? ((BOOL (*)(id, SEL))objc_msgSend)(o, sel_registerName(sel)) : NO; }
static id Y24_O0(id o, const char *sel) { return Y24_Has(o, sel) ? ((id (*)(id, SEL))objc_msgSend)(o, sel_registerName(sel)) : nil; }

// _SBRectContainsPoint: all four edges inclusive, a null rect contains nothing (G1D.x re-implements the same function)
static BOOL Y24_RectContainsPointInclusive(CGRect r, CGPoint p) {
    return !CGRectIsNull(r) && p.x >= CGRectGetMinX(r) && p.x <= CGRectGetMaxX(r) && p.y >= CGRectGetMinY(r) && p.y <= CGRectGetMaxY(r);
}

typedef id (*Y24GetDragItemFn)(id);
static Y24GetDragItemFn Y24_GetDragItem(void) {
    static Y24GetDragItemFn fn; static dispatch_once_t once;
    dispatch_once(&once, ^{ fn = (Y24GetDragItemFn)dlsym(RTLD_DEFAULT, "SBApplicationDropSessionGetDragItem"); });
    return fn;
}
static id Y24_BannerType(void) {
    static __unsafe_unretained id *slot; static dispatch_once_t once;
    dispatch_once(&once, ^{ slot = (__unsafe_unretained id *)dlsym(RTLD_DEFAULT, "NCUserNotificationDragPrivateTypeIdentifier"); });
    return slot ? *slot : nil;
}

// block 0x1c7707248 : screenEdgeForDragOverSideGutterRegionsAtLocation:inBounds:totalContentDragGutterWidth:screenInsets: != 0
static BOOL Y24_GutterHit(Class cls, id uiSession, CGPoint p, CGRect r, double width) {
    UIEdgeInsets insets = ((UIEdgeInsets (*)(id, SEL, id))objc_msgSend)((id)cls, sel_registerName("_screenInsetsForUIDragDropSession:"), uiSession);
    unsigned long long edge = ((unsigned long long (*)(id, SEL, CGPoint, CGRect, double, UIEdgeInsets))objc_msgSend)((id)cls,
        sel_registerName("screenEdgeForDragOverSideGutterRegionsAtLocation:inBounds:totalContentDragGutterWidth:screenInsets:"), p, r, width, insets);
    return edge != 0;
}

static BOOL Y24_Track(id selfCls, SEL _cmd, id session, id ctl, BOOL tracking) {
    Class cls = (Class)selfCls;
    if (!BP_OnName("y24_droptrack")) return gY24OrigTrack ? ((BOOL (*)(id, SEL, id, id, BOOL))gY24OrigTrack)(selfCls, _cmd, session, ctl, tracking) : NO;
    id uiSession = Y24_O0(session, "uiDragDropSession");
    // dragged application item (or a content drag that started at the screen edge, startLocation 8)
    if (Y24_LL0(Y24_O0(session, "localContext"), "startLocation") != 8) {
        Y24GetDragItemFn gi = Y24_GetDragItem();
        if (!gi || !gi(uiSession)) return NO;
    }
    id vcRaw = Y24_O0(ctl, "contentViewController");
    Class fluid = NSClassFromString(@"SBFluidSwitcherViewController");
    id vc = (fluid && [vcRaw isKindOfClass:fluid]) ? vcRaw : nil;            // _BSSafeCast
    id view = Y24_O0(vc, "view");
    id fixed = Y24_O0(Y24_O0(Y24_O0(view, "window"), "screen"), "fixedCoordinateSpace");
    CGPoint p = Y24_Has(uiSession, "locationInView:") ? ((CGPoint (*)(id, SEL, id))objc_msgSend)(uiSession, sel_registerName("locationInView:"), view) : CGPointZero;
    CGPoint pScreen = Y24_Has(view, "convertPoint:toCoordinateSpace:") ? ((CGPoint (*)(id, SEL, CGPoint, id))objc_msgSend)(view, sel_registerName("convertPoint:toCoordinateSpace:"), p, fixed) : CGPointZero;
    // a drag of a notification banner over the banner frame (inflated by 50) is not tracked
    id bannerType = Y24_BannerType();
    if (bannerType && Y24_Has(uiSession, "hasItemsConformingToTypeIdentifiers:") && ((BOOL (*)(id, SEL, id))objc_msgSend)(uiSession, sel_registerName("hasItemsConformingToTypeIdentifiers:"), @[ bannerType ])) {
        id dispatcher = Y24_O0(BPX_App(), "notificationDispatcher");
        CGRect banner = Y24_Rect0(Y24_O0(dispatcher, "bannerDestination"), "presentedBannerScreenFrame");
        if (CGRectContainsPoint(CGRectInset(banner, -50, -50), pScreen)) return NO;
    } else if (!bannerType) Y17_GuardOnce("droptrack", nil, "NCUserNotificationDragPrivateTypeIdentifier");
    CGRect bounds = Y24_Rect0(view, "bounds");
    if (!CGRectContainsPoint(UIEdgeInsetsInsetRect(bounds, UIEdgeInsetsMake(0.5, 0.5, 0.5, 0.5)), p)) return NO;      // (1) new in 16.2
    long long zones = Y24_LL0(session, "dropZones");
    if (Y24_B0(ctl, "isChamoisWindowingUIEnabled")) {
        BOOL strip = NO;
        if (Y24_B0(vc, "_areContinuousExposeStripsUnoccluded")) {                                                         // (2) new in 16.2
            double sw = Y24_D0(Y24_O0(vc, "chamoisLayoutAttributes"), "stripWidth");
            if (Y24_LL0(BPX_App(), "userInterfaceLayoutDirection") == 1) strip = p.x > CGRectGetMaxX(bounds) - sw;
            else strip = p.x < CGRectGetMinX(bounds) + sw;
        }
        if (zones == 1) {                                                                                                // (3) new in 16.2
            id container = Y24_Has(vc, "_itemContainerAtLocation:environment:") ? ((id (*)(id, SEL, CGPoint, long long))objc_msgSend)(vc, sel_registerName("_itemContainerAtLocation:environment:"), p, 0) : nil;
            if (!container) return !strip;
            CGSize sz = Y24_Has(container, "size") ? ((CGSize (*)(id, SEL))objc_msgSend)(container, sel_registerName("size")) : CGSizeZero;
            if (sz.width != bounds.size.width || sz.height != bounds.size.height) return NO;
        } else if (zones == 0) return !strip;
    }
    BOOL region = ((BOOL (*)(id, SEL, CGPoint, CGRect))objc_msgSend)((id)cls, sel_registerName("isDragOverFullscreenRegionAtLocation:inBounds:"), p, bounds);
    if (zones == 0) return YES;
    if (zones == 2) {                                                                                                    // window tear off
        double side = Y24_D0((id)cls, "prototypeSettingsWindowTearOffDraggingSideActivationWidth");
        double floating = Y24_D0((id)cls, "prototypeSettingsWindowTearOffDraggingFloatingActivationWidth");
        CGRect src = ((CGRect (*)(id, SEL, id, id))objc_msgSend)((id)cls, sel_registerName("sourceSceneInterfaceOrientedBoundsForDropSession:switcherController:"), session, ctl);
        if (CGRectIsNull(src)) return YES;
        if (region || !CGRectContainsPoint(src, p)) return YES;
        return Y24_GutterHit(cls, uiSession, p, src, (side + floating) * (src.size.width / bounds.size.width));
    }
    if (zones != 1) return NO;
    double gutter = tracking ? Y24_D0((id)cls, "prototypeSettingsContentDraggingSideActivationWidth") + Y24_D0((id)cls, "prototypeSettingsContentDraggingFloatingActivationWidth")
                             : Y24_D0((id)cls, "prototypeSettingsContentDraggingCommandeerWidth");
    if (!region && !Y24_GutterHit(cls, uiSession, p, bounds, gutter)) return NO;
    // content drag: the element under the finger must not exclude the location (multitaskingDragExclusionRects of its scene)
    id state = Y24_O0(ctl, "layoutState");
    id found = nil;
    CGRect foundFrame = CGRectZero;
    static const long long roles[] = { 1, 2, 4, 5, 6, 7, 8, 9, 3 };                                                      // _SBLayoutRoleEnumerateValidRoles
    for (size_t i = 0; i < sizeof roles / sizeof roles[0]; i++) {
        long long role = roles[i];
        if (found && Y24_LL0(found, "layoutRole") == 3) continue;
        id el = Y24_Has(state, "elementWithRole:") ? ((id (*)(id, SEL, long long))objc_msgSend)(state, sel_registerName("elementWithRole:"), role) : nil;
        if (!el) continue;
        CGRect f;
        if (role == 3) {
            long long orient = Y24_LL0(state, "interfaceOrientation");
            long long cfg = Y24_LL0(state, "floatingConfiguration");
            f = Y24_Has(ctl, "frameForFloatingAppLayoutInInterfaceOrientation:floatingConfiguration:") ? ((CGRect (*)(id, SEL, long long, long long))objc_msgSend)(ctl, sel_registerName("frameForFloatingAppLayoutInInterfaceOrientation:floatingConfiguration:"), orient, cfg) : CGRectZero;
        } else {
            id mainLayout = Y24_O0(state, "appLayout");
            long long orient = Y24_LL0(state, "interfaceOrientation");
            f = Y24_Has(ctl, "frameForItemWithRole:inMainAppLayout:interfaceOrientation:") ? ((CGRect (*)(id, SEL, long long, id, long long))objc_msgSend)(ctl, sel_registerName("frameForItemWithRole:inMainAppLayout:interfaceOrientation:"), role, mainLayout, orient) : CGRectZero;
        }
        if (Y24_RectContainsPointInclusive(f, p)) { found = el; foundFrame = f; }
    }
    id sceneID = Y24_O0(found, "uniqueIdentifier");
    id fbm = Y24_O0((id)NSClassFromString(@"FBSceneManager"), "sharedInstance");
    id scene = (sceneID && Y24_Has(fbm, "sceneWithIdentifier:")) ? ((id (*)(id, SEL, id))objc_msgSend)(fbm, sel_registerName("sceneWithIdentifier:"), sceneID) : nil;
    if (!scene) return YES;
    id cs = Y24_O0(scene, "clientSettings");
    if (!Y24_B0(cs, "isUISubclass")) return YES;
    CGRect sceneRect = Y24_Has(view, "convertRect:toCoordinateSpace:") ? ((CGRect (*)(id, SEL, CGRect, id))objc_msgSend)(view, sel_registerName("convertRect:toCoordinateSpace:"), foundFrame, fixed) : CGRectZero;
    id exclusions = Y24_O0(cs, "multitaskingDragExclusionRects");
    Class space = NSClassFromString(@"SBSceneLayoutCoordinateSpace");
    for (id v in (exclusions ?: @[])) {
        CGRect r = [v CGRectValue];
        id local = Y24_Has((id)space, "coordinateSpaceForFrame:withinCoordinateSpace:") ? ((id (*)(id, SEL, CGRect, id))objc_msgSend)((id)space, sel_registerName("coordinateSpaceForFrame:withinCoordinateSpace:"), sceneRect, fixed) : nil;
        CGRect inScreen = Y24_Has(local, "convertRect:toCoordinateSpace:") ? ((CGRect (*)(id, SEL, CGRect, id))objc_msgSend)(local, sel_registerName("convertRect:toCoordinateSpace:"), r, fixed) : CGRectNull;
        if (!CGRectIsNull(inScreen) && CGRectContainsPoint(inScreen, pScreen)) return NO;
    }
    return YES;
}

__attribute__((constructor)) static void Y24Drag_Setup(void) {
    if (!BPY_BuildOK()) return;
    @autoreleasepool {
        Class c = NSClassFromString(@"SBDragAndDropWorkspaceTransaction");
        Class meta = c ? object_getClass((id)c) : Nil;
        SEL sel = sel_registerName("_shouldTrackLocationOfDropSession:forSwitcherController:isCurrentlyTracking:");
        NSMutableArray *missing = [NSMutableArray array];
        if (!meta || !class_getInstanceMethod(meta, sel)) [missing addObject:@"+[SBDragAndDropWorkspaceTransaction _shouldTrackLocationOfDropSession:forSwitcherController:isCurrentlyTracking:]"];
        static const char *classSels[] = { "_screenInsetsForUIDragDropSession:", "screenEdgeForDragOverSideGutterRegionsAtLocation:inBounds:totalContentDragGutterWidth:screenInsets:",
            "isDragOverFullscreenRegionAtLocation:inBounds:", "sourceSceneInterfaceOrientedBoundsForDropSession:switcherController:", "prototypeSettingsWindowTearOffDraggingSideActivationWidth",
            "prototypeSettingsWindowTearOffDraggingFloatingActivationWidth", "prototypeSettingsContentDraggingSideActivationWidth", "prototypeSettingsContentDraggingFloatingActivationWidth",
            "prototypeSettingsContentDraggingCommandeerWidth" };
        for (size_t i = 0; i < sizeof classSels / sizeof classSels[0]; i++) if (!meta || !class_getInstanceMethod(meta, sel_registerName(classSels[i]))) [missing addObject:[NSString stringWithFormat:@"+[SBDragAndDropWorkspaceTransaction %s]", classSels[i]]];
        Class fluid = NSClassFromString(@"SBFluidSwitcherViewController");
        static const char *vcSels[] = { "_areContinuousExposeStripsUnoccluded", "chamoisLayoutAttributes", "_itemContainerAtLocation:environment:" };
        for (size_t i = 0; i < sizeof vcSels / sizeof vcSels[0]; i++) if (!fluid || !class_getInstanceMethod(fluid, sel_registerName(vcSels[i]))) [missing addObject:[NSString stringWithFormat:@"-[SBFluidSwitcherViewController %s]", vcSels[i]]];
        if (!Y24_GetDragItem()) [missing addObject:@"SBApplicationDropSessionGetDragItem"];
        if (!dlsym(RTLD_DEFAULT, "NCUserNotificationDragPrivateTypeIdentifier")) [missing addObject:@"NCUserNotificationDragPrivateTypeIdentifier"];
        if (missing.count) { BP_Log(@"[y24] GUARD(droptrack) not installed, missing: %@ (the 16.0 body keeps running)", missing); return; }
        gY24OrigTrack = BPX_Replace(meta, "_shouldTrackLocationOfDropSession:forSwitcherController:isCurrentlyTracking:", (IMP)Y24_Track);
        BP_Log(@"[y24] installed y24_droptrack (orig %p)", (void *)gY24OrigTrack);
    }
}
#pragma clang diagnostic pop
