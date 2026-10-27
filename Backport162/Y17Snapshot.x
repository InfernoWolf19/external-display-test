// Y17Snapshot.x : delta sweep pass 2, family SBAppSwitcherSnapshotImageCache (specs/DELTA-SWEEP-0.7.9.md rows of the cache).  Setup: constructor.  Log prefix "[y17s]".
//
//  y17_snapscale    -[SBAppSwitcherSnapshotImageCache _loadSnapshotForRequest:withDisplayItem:inAppLayout:] 16.2 0x1c72b7a54 (16.0 0x1c5e45610).  16.0 reads the scale of the snapshot to look for from
//                   +[FBDisplayManager mainConfiguration] (0x1c5e4575c) = the iPad's panel, for every cache.  16.2 asks the cache delegate for -displayIdentityForImageCache: (the switcher view controller:
//                   its window scene's scene manager displayIdentity, identical in 16.0 0x1c5fd7b3c and 16.2 0x1c7450d44), takes [[FBDisplayManager sharedInstance] configurationForIdentity:] and its -scale
//                   (0x1c72b7bb8..0x1c72b7bdc, used at 0x1c72b7e3c as the scale: of -[SBApplication bestSnapshotWithImageName:sceneHandle:variantID:scale:referenceSize:requireExactSize:
//                   contentTypeMask:statusBarStateMask:launchingOrientation:contentOverridesContext:userInterfaceStyle:displayEdgeInfo:]).  The classic launch size of 16.2 still comes from
//                   [[UIScreen mainScreen] displayConfiguration] (0x1c72b7c4c), i.e. the same configuration 16.0 uses, so ONLY the scale changes.  The scale of 16.0 is used for nothing else in the method
//                   (the only use of d10 is the scale: argument).  Ported: a wrapper around the 16.0 body sets a thread local override that the hook of bestSnapshotWithImageName:...scale:... applies
//                   (the call is made inline on the main thread by the same method).  Windows of the monitor get snapshots looked up at the monitor's scale.
//  y17_snapentity   -[SBAppSwitcherSnapshotImageCache _representedApplicationSceneEntityForDisplayItem:] 16.2 0x1c72b84f4 (16.0 0x1c5e45fdc): 16.0 builds the SBDeviceApplicationSceneEntity even when
//                   the delegate has no scene handle provider; 16.2 (0x1c72b85c8..0x1c72b85ec) logs a fault (os_log type 0x11, _SBLogSwitcherSnapshotCache) and returns nil when the application
//                   exists but the provider is nil.  Ported: wrapper with the same early out (logged).
//  y17_snapreload   -[SBAppSwitcherSnapshotImageCache reloadSnapshotsForInterfaceStyleChange:] 16.2 0x1c77a12d4 (16.0 0x1c6303860): 16.2 reloads with dispatch_sync on the control queue, 16.0 with
//                   dispatch_async, so the cache is already cleared / re-requested when the style change call returns.  Ported: the 16.0 body, then a barrier (empty dispatch_sync on _controlQueue).
//  Rows decided EQUIVALENT (no code): _cacheSnapshotForRequest:, _asynchronouslyLoadSnapshotFromRequest:, _snapshotImage:finishedLoadingForRequest:, _createDownscaledVariantForRequest:...,
//                   setCachableAppLayouts: / cachableAppLayouts / setFullSizeCachableAppLayouts: / fullSizeCachableAppLayouts: the normalised diff (ds/dd.py, 16.0 -> 16.2) of these ten
//                   methods contains only _objc_initWeak / copyWeak / destroyWeak of self for the blocks (16.2 captures self weakly, 16.0 strongly: the cache is kept alive until the queued work ran
//                   instead of the work being dropped) and _BSDispatchQueueAssertMain() (a debug assertion that the main thread calls it) plus, in _asynchronouslyLoadSnapshotFromRequest:, the
//                   UIImage conversion (-_uiImageForCGImage:forSnapshotRequest:) done before instead of inside the dispatch to the control queue (same image, other thread).  No snapshot, scale, size
//                   or ordering differs.
// Needs a device: with a window on the monitor, the switcher snapshots (app switcher / Stage Manager strip / window container placeholder) of the monitor are looked up at the monitor's scale
// (log lines "[y17s] snapshot scale ...").

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "Y17Common.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

typedef struct { double w, h; } Y17Size;

static IMP gY17OrigLoad, gY17OrigBest, gY17OrigRep, gY17OrigReload;
static __thread BOOL tY17ScaleOn;
static __thread double tY17Scale;

// -[SBAppSwitcherSnapshotImageCache _loadSnapshotForRequest:withDisplayItem:inAppLayout:]
static void Y17_Load(id self, SEL _cmd, id request, id item, id layout) {
    BOOL saved = tY17ScaleOn;
    double savedScale = tY17Scale;
    if (BP_OnName("y17_snapscale")) {
        id delegate = Y17_Obj0("snapscale", self, "delegate");
        id identity = Y17_Obj1("snapscale", delegate, "displayIdentityForImageCache:", self);
        double s = identity ? Y17_ScaleForIdentity("snapscale", identity) : 0;
        if (s > 0) {
            tY17ScaleOn = YES;
            tY17Scale = s;
            BPY_LOG(@"[y17s] snapshot scale %.2f for %@ (display identity %@)", s, item, identity);
        } else {
            BP_Log(@"[y17s] GUARD(snapscale) no display scale for the cache of %@ (identity %@): the 16.0 main configuration scale stays", item, identity);
        }
    }
    if (gY17OrigLoad) ((void (*)(id, SEL, id, id, id))gY17OrigLoad)(self, _cmd, request, item, layout);
    tY17ScaleOn = saved;
    tY17Scale = savedScale;
}

// -[SBApplication bestSnapshotWithImageName:sceneHandle:variantID:scale:referenceSize:requireExactSize:contentTypeMask:statusBarStateMask:launchingOrientation:contentOverridesContext:userInterfaceStyle:displayEdgeInfo:]
static id Y17_Best(id self, SEL _cmd, id name, id handle, id variant, double scale, Y17Size size, BOOL exact, unsigned long long cmask, unsigned long long smask, long long orient, id ctx, long long style, id info) {
    if (tY17ScaleOn) scale = tY17Scale;
    return gY17OrigBest ? ((id (*)(id, SEL, id, id, id, double, Y17Size, BOOL, unsigned long long, unsigned long long, long long, id, long long, id))gY17OrigBest)(self, _cmd, name, handle, variant, scale, size, exact, cmask, smask, orient, ctx, style, info) : nil;
}

// -[SBAppSwitcherSnapshotImageCache _representedApplicationSceneEntityForDisplayItem:]
static id Y17_Rep(id self, SEL _cmd, id item) {
    id r = gY17OrigRep ? ((id (*)(id, SEL, id))gY17OrigRep)(self, _cmd, item) : nil;
    if (r && BP_OnName("y17_snapentity") && BPX_Obj0(r, "application")) {
        id delegate = Y17_Obj0("snapentity", self, "delegate");
        if (delegate && ![delegate respondsToSelector:sel_registerName("sceneHandleProviderForImageCache:")]) {
            Y17_GuardOnce("snapentity", delegate, "sceneHandleProviderForImageCache:");
        } else if (delegate && !Y17_Obj1("snapentity", delegate, "sceneHandleProviderForImageCache:", self)) {
            BP_Log(@"[y17s] snapshot cache %@: no scene handle provider for %@, no scene entity (16.2 0x1c72b85c8)", self, item);
            return nil;
        }
    }
    return r;
}

// -[SBAppSwitcherSnapshotImageCache reloadSnapshotsForInterfaceStyleChange:]
static void Y17_Reload(id self, SEL _cmd, long long style) {
    if (gY17OrigReload) ((void (*)(id, SEL, long long))gY17OrigReload)(self, _cmd, style);
    if (!BP_OnName("y17_snapreload")) return;
    Ivar iv = class_getInstanceVariable(object_getClass(self), "_controlQueue");
    id q = iv ? object_getIvar(self, iv) : nil;
    if (q) {
        dispatch_sync((dispatch_queue_t)q, ^{});
        BPY_LOG(@"[y17s] reloadSnapshotsForInterfaceStyleChange:%lld drained the control queue (16.2: dispatch_sync)", style);
    } else {
        BP_Log(@"[y17s] GUARD(snapreload) _controlQueue ivar missing on the snapshot cache: asynchronous reload of 16.0 stays");
    }
}

__attribute__((constructor)) static void Y17S_Setup(void) {
    if (!BPY_BuildOK()) return;
    @autoreleasepool {
        int n = 0;
        Class cc = NSClassFromString(@"SBAppSwitcherSnapshotImageCache"), app = NSClassFromString(@"SBApplication");
        const char *best = "bestSnapshotWithImageName:sceneHandle:variantID:scale:referenceSize:requireExactSize:contentTypeMask:statusBarStateMask:launchingOrientation:contentOverridesContext:userInterfaceStyle:displayEdgeInfo:";
        if (cc && app && class_getInstanceMethod(app, sel_registerName(best)) && class_getInstanceMethod(cc, sel_registerName("_loadSnapshotForRequest:withDisplayItem:inAppLayout:"))) {
            gY17OrigBest = BPX_Replace(app, best, (IMP)Y17_Best);
            gY17OrigLoad = BPX_Replace(cc, "_loadSnapshotForRequest:withDisplayItem:inAppLayout:", (IMP)Y17_Load);
            n++;
        } else BP_Log(@"[y17s] GUARD(snapscale) SBApplication bestSnapshot... or the cache load method is missing: y17_snapscale not installed");
        if (cc && class_getInstanceMethod(cc, sel_registerName("_representedApplicationSceneEntityForDisplayItem:"))) {
            gY17OrigRep = BPX_Replace(cc, "_representedApplicationSceneEntityForDisplayItem:", (IMP)Y17_Rep);
            n++;
        } else BP_Log(@"[y17s] GUARD(snapentity) _representedApplicationSceneEntityForDisplayItem: missing: y17_snapentity not installed");
        if (cc && class_getInstanceMethod(cc, sel_registerName("reloadSnapshotsForInterfaceStyleChange:"))) {
            gY17OrigReload = BPX_Replace(cc, "reloadSnapshotsForInterfaceStyleChange:", (IMP)Y17_Reload);
            n++;
        } else BP_Log(@"[y17s] GUARD(snapreload) reloadSnapshotsForInterfaceStyleChange: missing: y17_snapreload not installed");
        BP_Log(@"[y17s] installed %d of 3 (switches y17_snapscale, y17_snapentity, y17_snapreload)", n);
    }
}
#pragma clang diagnostic pop
