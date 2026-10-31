// Y30Snapshot.x : delta sweep pass 3, switcher snapshots of classic (iPhone-only) apps (F3).  Setup: constructor.  Log prefix "[y30]".
//
//  y24_snapstretch  Non uniform ("stretched") scaling of the snapshot of a classic app in the full screen scaled mode.
//      -[SBAppSwitcherReusableSnapshotView _doNonUniformScalingForApplication:]  16.2 0x1c7921848 (new): YES when (MGIsDeviceOfType(A) || MGIsDeviceOfType(B)) && !_isChamoisWindowingEnabled &&
//             !app.classicAppPhoneAppRunningOnPad && app.classicAppScaled && app.classicAppFullScreen.  A and B are the two 20 byte device type hashes at 0x1c7a93748 + word 0x937e7e75 and
//             0x1c7a9375c + word 0xc81c8d74 (stack words 0x1c7921880 / 0x1c79218a8), passed to libMobileGestalt's MGIsDeviceOfType.
//      -[SBAppSwitcherReusableSnapshotView _snapshotImageFrameForCacheEntry:]  16.2 0x1c72a7a60 (16.0 0x1c5e35608): the classic frame branch (snapshotFrameForClassicInsideBounds: ...) is skipped when
//             the suspend snapshot test, the Stage Manager flag or _doNonUniformScalingForApplication: say so; the answer is then the plain layout frame computed first
//             (-_frameInLayoutSpaceForRole:inAppLayout:inOrientation:, 0x1c72a7b8c).  Ported as a wrapper: in exactly that case the layout frame is answered, otherwise the 16.0 body runs.
//      -[SBSwitcherSnapshotImageView setImage:] (16.2 0x1c72c2b48) sends sizeToFit to the image view after setting the image; -layoutSubviews (16.2 0x1c72a6254, 16.0 0x1c5e33de8) always sizes the
//             image view to fit first and, with _stretchToFillBounds, then sets its bounds to the container bounds transformed by the inverted scaling transform (16.0 sized to fit only without
//             the flag).  Re-implemented from the 16.2 body.
// Needs a device: a classic (iPhone-only) app in the app switcher with Stage Manager off on the two device types above: its card is stretched instead of letterboxed.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import "Y17Common.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

static IMP gY30OrigFrame, gY30OrigSetImage, gY30OrigLayout;

static BOOL Y30_BoolIvar(id o, const char *name) {
    Ivar iv = o ? class_getInstanceVariable(object_getClass(o), name) : NULL;
    if (!iv) { Y17_GuardOnce("snapstretch", o, name); return NO; }
    return *(BOOL *)((char *)(__bridge void *)o + ivar_getOffset(iv));
}
static id Y30_ObjIvar(id o, const char *name) {
    Ivar iv = o ? class_getInstanceVariable(object_getClass(o), name) : NULL;
    if (!iv) { Y17_GuardOnce("snapstretch", o, name); return nil; }
    return BP_ObjIvar(o, iv);
}

typedef BOOL (*Y30_MGFn)(const void *);
static BOOL Y30_NonUniform(id view, id app) {
    static Y30_MGFn mg; static dispatch_once_t once;
    dispatch_once(&once, ^{ mg = (Y30_MGFn)dlsym(RTLD_DEFAULT, "MGIsDeviceOfType"); if (!mg) BP_Log(@"[y30] GUARD(snapstretch) MGIsDeviceOfType does not resolve: the non uniform scaling is never applied"); });
    if (!mg) return NO;
    static const unsigned char devA[20] = { 0xd3, 0xb5, 0xff, 0xca, 0x33, 0xe4, 0x60, 0x44, 0x60, 0x65, 0x5a, 0xdf, 0xd7, 0x7f, 0xdf, 0xa4, 0x75, 0x7e, 0x7e, 0x93 };
    static const unsigned char devB[20] = { 0x96, 0xc2, 0x6a, 0xe5, 0x14, 0x3d, 0x44, 0x62, 0xc0, 0x91, 0x51, 0xca, 0x85, 0xb7, 0x95, 0x7d, 0x74, 0x8d, 0x1c, 0xc8 };
    BOOL a = mg(devA);
    BOOL b = mg(devB);
    if (!a && !b) return NO;
    if (Y30_BoolIvar(view, "_isChamoisWindowingEnabled")) return NO;
    if (!app) return NO;
    if (BPY_Responds(app, "classicAppPhoneAppRunningOnPad") && BPY_SEND(BOOL, (), app, "classicAppPhoneAppRunningOnPad")) return NO;
    if (!BPY_Responds(app, "classicAppScaled") || !BPY_SEND(BOOL, (), app, "classicAppScaled")) return NO;
    return BPY_Responds(app, "classicAppFullScreen") ? BPY_SEND(BOOL, (), app, "classicAppFullScreen") : NO;
}

static CGRect Y30_ImageFrame(id self, SEL _cmd, id entry) {
    if (BP_OnName("y24_snapstretch") && entry && BPY_Responds(self, "_isSnapshotSuspendSnapshot:") && BPY_Responds(self, "_applicationForRole:") && BPY_Responds(self, "_frameInLayoutSpaceForRole:inAppLayout:inOrientation:")) {
        id snapshot = Y17_Obj0("snapstretch", entry, "snapshot");
        if (!BPY_SEND(BOOL, (id), self, "_isSnapshotSuspendSnapshot:", snapshot) && !Y30_BoolIvar(self, "_isChamoisWindowingEnabled")) {
            id app = BPY_SEND(id, (long long), self, "_applicationForRole:", BPX_LL0(entry, "role"));
            if (Y30_NonUniform(self, app)) {
                id layout = Y17_Obj0("snapstretch", entry, "appLayout");
                long long role = BPY_Responds(layout, "layoutRoleForItem:") ? BPY_SEND(long long, (id), layout, "layoutRoleForItem:", Y17_Obj0("snapstretch", entry, "displayItem")) : 0;
                CGRect f = BPY_SEND(CGRect, (long long, id, long long), self, "_frameInLayoutSpaceForRole:inAppLayout:inOrientation:", role, layout, BPX_LL0(self, "orientation"));
                BPY_LOG(@"[y30] classic snapshot of %@ stretched (non uniform scaling)", app);
                return f;
            }
        }
    }
    return gY30OrigFrame ? ((CGRect (*)(id, SEL, id))gY30OrigFrame)(self, _cmd, entry) : CGRectZero;
}

static void Y30_SetImage(id self, SEL _cmd, id image) {
    if (gY30OrigSetImage) ((void (*)(id, SEL, id))gY30OrigSetImage)(self, _cmd, image);
    if (!BP_OnName("y24_snapstretch")) return;
    id imageView = Y30_ObjIvar(self, "_imageView");
    if (BPY_Responds(imageView, "sizeToFit")) BPY_SEND(void, (), imageView, "sizeToFit");
}
static void Y30_Layout(id self, SEL _cmd) {
    if (!BP_OnName("y24_snapstretch")) { if (gY30OrigLayout) ((void (*)(id, SEL))gY30OrigLayout)(self, _cmd); return; }
    id container = Y30_ObjIvar(self, "_scalingView");
    id imageView = Y30_ObjIvar(self, "_imageView");
    if (!container || !imageView || !BPY_Responds(self, "scalingTransform") || !BPY_Responds(self, "_updateCornerRadius")) {
        Y17_GuardOnce("snapstretch", self, "_scalingView / _imageView / scalingTransform: 16.0 layout");
        if (gY30OrigLayout) ((void (*)(id, SEL))gY30OrigLayout)(self, _cmd);
        return;
    }
    CGRect bounds = BPY_SEND(CGRect, (), self, "bounds");
    BPY_SEND(void, (CGRect), container, "setBounds:", bounds);
    BPY_SEND(void, (CGPoint), container, "setCenter:", CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds)));       // _UIRectGetCenter
    BPY_SEND(void, (), imageView, "sizeToFit");
    CGAffineTransform t = BPY_SEND(CGAffineTransform, (), self, "scalingTransform");
    if (Y30_BoolIvar(self, "_stretchToFillBounds")) {
        CGRect scaled = CGRectApplyAffineTransform(bounds, CGAffineTransformInvert(t));
        BPY_SEND(void, (CGRect), imageView, "setBounds:", scaled);
    }
    CGPoint center = BPY_SEND(CGPoint, (), container, "center");
    BPY_SEND(void, (CGPoint), imageView, "setCenter:", center);
    BPY_SEND(void, (CGAffineTransform), imageView, "setTransform:", t);
    BPY_SEND(void, (), self, "_updateCornerRadius");
}

__attribute__((constructor)) static void Y30_Setup(void) {
    if (!BPY_BuildOK()) return;
    @autoreleasepool {
        int n = 0;
        Class rv = NSClassFromString(@"SBAppSwitcherReusableSnapshotView");
        if (rv && class_getInstanceMethod(rv, sel_registerName("_snapshotImageFrameForCacheEntry:"))) { gY30OrigFrame = BPX_Replace(rv, "_snapshotImageFrameForCacheEntry:", (IMP)Y30_ImageFrame); n++; }
        else BP_Log(@"[y30] GUARD(snapstretch) SBAppSwitcherReusableSnapshotView _snapshotImageFrameForCacheEntry: missing: not installed");
        Class iv = NSClassFromString(@"SBSwitcherSnapshotImageView");
        if (iv && class_getInstanceMethod(iv, sel_registerName("setImage:")) && class_getInstanceMethod(iv, sel_registerName("layoutSubviews"))) {
            gY30OrigSetImage = BPX_Replace(iv, "setImage:", (IMP)Y30_SetImage);
            gY30OrigLayout = BPX_Replace(iv, "layoutSubviews", (IMP)Y30_Layout); n++;
        } else BP_Log(@"[y30] GUARD(snapstretch) SBSwitcherSnapshotImageView setImage: / layoutSubviews missing: not installed");
        BP_Log(@"[y30] installed %d group(s) (switch y24_snapstretch)", n);
    }
}
#pragma clang diagnostic pop
