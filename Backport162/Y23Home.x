// Y23Home.x : delta sweep pass 2, Home Screen / Icon (F2).  Setup: constructor.  Log prefix "[y23]".
//
//  y17_applibrary  -[SBIconController _appLibraryListLayoutProviderForWindowScene:] 16.2 0x1c749bb60 (16.0 0x1c60211c4).  The App Library of a window scene that is not the main display uses
//                  list layouts whose expanded category pod has doubled side insets.  16.0 builds the provider from the SHARED layouts of the icon manager and then calls -setPortraitLayoutInsets: on
//                  [[layout layoutConfiguration] ...] of the shared expanded pod layout (0x1c60213dc): the configuration object belongs to the layout the iPad's own App Library uses, so the first App
//                  Library on the monitor changed the iPad's expanded pod insets for good.  16.2 (0x1c749bc28..) copies the configuration, creates a new SBIconListGridLayout from the copy and
//                  puts that one into the dictionary of the new provider for the expanded pod location only.
//                  The seven locations (GOT slots 0x1d84cfa30.. in 16.0, 0x1d840bb68.. in 16.2, all consecutive, in the alphabetical order of the imports of SpringBoardHome) are
//                  SBIconLocationAppLibrary, ...AppLibraryCategoryPod, ...CategoryPodAdditionalItems, ...CategoryPodExpanded, ...CategoryPodRecents, ...CategoryPodSuggestions, SBIconLocationAppLibrarySearch;
//                  the modified one is the fourth, ...CategoryPodExpanded (16.0 slot 0xa48 loaded into x25 at 0x1c60212f8, 16.2 slot 0xb80 into x24 at 0x1c749bbe0).  The new insets keep top and bottom
//                  of the portrait insets and take twice the left and right of the landscape insets (fadd d1,d8,d8 / fadd d3,d9,d9).
// Needs a device: open the App Library on the monitor, then on the iPad: the iPad's expanded category pod keeps its own insets.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import "Y17Common.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

typedef struct { double top, left, bottom, right; } Y23Insets;

static IMP gY23Orig;

static id Y23_Location(const char *sym) {
    void *p = dlsym(RTLD_DEFAULT, sym);
    return p ? *(__unsafe_unretained id *)p : nil;
}

static id Y23_ProviderForScene(id self, SEL _cmd, id scene) {
    id orig = nil;
    if (!BP_OnName("y17_applibrary")) return gY23Orig ? ((id (*)(id, SEL, id))gY23Orig)(self, _cmd, scene) : nil;
    id manager = BPX_Obj0(self, "iconManager");
    id provider = BPX_Obj0(manager, "listLayoutProvider");
    if ([scene respondsToSelector:sel_registerName("isMainDisplayWindowScene")] && BPX_Bool0(scene, "isMainDisplayWindowScene")) return provider;
    static const char *names[7] = { "SBIconLocationAppLibrary", "SBIconLocationAppLibraryCategoryPod", "SBIconLocationAppLibraryCategoryPodAdditionalItems", "SBIconLocationAppLibraryCategoryPodExpanded",
        "SBIconLocationAppLibraryCategoryPodRecents", "SBIconLocationAppLibraryCategoryPodSuggestions", "SBIconLocationAppLibrarySearch" };
    id locs[7];
    for (int i = 0; i < 7; i++) {
        locs[i] = Y23_Location(names[i]);
        if (!locs[i]) { BP_Log(@"[y23] GUARD(applibrary) icon location symbol %s not found: the 16.0 provider builder runs", names[i]); goto fallback; }
    }
    {
        Class grid = NSClassFromString(@"SBIconListGridLayout");
        id base = BPX_Obj1(provider, "layoutForIconLocation:", locs[3]);
        if (!grid || ![base isKindOfClass:grid]) { BP_Log(@"[y23] GUARD(applibrary) expanded pod layout %@ is not an SBIconListGridLayout: the 16.0 provider builder runs", base); goto fallback; }
        id cfg = [BPX_Obj0(base, "layoutConfiguration") copy];
        if (!cfg || !BPY_Responds(cfg, "landscapeLayoutInsets") || !BPY_Responds(cfg, "portraitLayoutInsets") || !BPY_Responds(cfg, "setPortraitLayoutInsets:") ||
            ![grid instancesRespondToSelector:sel_registerName("initWithLayoutConfiguration:")]) { BP_Log(@"[y23] GUARD(applibrary) layout configuration %@ lacks the insets API: the 16.0 provider builder runs", cfg); goto fallback; }
        Y23Insets land = ((Y23Insets (*)(id, SEL))objc_msgSend)(cfg, sel_registerName("landscapeLayoutInsets"));
        Y23Insets port = ((Y23Insets (*)(id, SEL))objc_msgSend)(cfg, sel_registerName("portraitLayoutInsets"));
        port.left = land.left + land.left;
        port.right = land.right + land.right;
        ((void (*)(id, SEL, Y23Insets))objc_msgSend)(cfg, sel_registerName("setPortraitLayoutInsets:"), port);
        id fresh = ((__attribute__((ns_returns_retained)) id (*)(__attribute__((ns_consumed)) id, SEL, id))objc_msgSend)([grid alloc], sel_registerName("initWithLayoutConfiguration:"), cfg);
        NSMutableDictionary *layouts = [NSMutableDictionary dictionaryWithCapacity:7];
        for (int i = 0; i < 7; i++) {
            id l = (i == 3) ? fresh : BPX_Obj1(provider, "layoutForIconLocation:", locs[i]);
            if (!l) { BP_Log(@"[y23] GUARD(applibrary) no layout for %s: the 16.0 provider builder runs", names[i]); goto fallback; }
            layouts[locs[i]] = l;
        }
        Class pc = object_getClass(provider);
        SEL ini = sel_registerName("initWithListLayouts:");
        if (!pc || ![pc instancesRespondToSelector:ini]) { BP_Log(@"[y23] GUARD(applibrary) provider class %@ has no initWithListLayouts:", pc); goto fallback; }
        id result = ((__attribute__((ns_returns_retained)) id (*)(__attribute__((ns_consumed)) id, SEL, id))objc_msgSend)([pc alloc], ini, layouts);
        BPY_LOG(@"[y23] app library provider for the scene %@: private expanded pod layout, side insets %.1f / %.1f (the shared layout is not touched)", scene, port.left, port.right);
        return result;
    }
fallback:
    orig = gY23Orig ? ((id (*)(id, SEL, id))gY23Orig)(self, _cmd, scene) : nil;
    return orig;
}

// ---- y17_sbrecording ----
//  -[SBMainDisplaySceneLayoutStatusBarView _applyStatusBarAlpha:toSceneWithIdentifier:] / _applyStatusBarHidden:withAnimation:toSceneWithIdentifier: 16.2 0x1c7542ad0 / 0x1c7542248
//  (16.0 0x1c60be3f8 / 0x1c60bdb80): after the status bar parts changed, 16.2 calls -updateRecordingIndicatorForStatusBarChanges on [[self _sbWindowScene] recordingIndicatorManager] (the manager of the
//  view's own window scene, X5Recording.x gives every external scene one); 16.0 asks [SBApp recordingIndicatorManagerForMainDisplay].  Ported: after the 16.0 body the own scene manager is updated
//  as well (immediately and once more on the next main queue turn, the hide path applies inside an animation handler), when it is not the main display's manager.
static IMP gY23OrigAlpha, gY23OrigHidden;
static void Y23_UpdateOwnIndicator(id view) {
    id scene = BPX_Obj0(view, "_sbWindowScene");
    id mgr = BPX_Obj0(scene, "recordingIndicatorManager");
    id mainMgr = BPX_Obj0(BPX_App(), "recordingIndicatorManagerForMainDisplay");
    if (!mgr || mgr == mainMgr || !BPY_Responds(mgr, "updateRecordingIndicatorForStatusBarChanges")) return;
    BPY_SEND(void, (), mgr, "updateRecordingIndicatorForStatusBarChanges");
}
static void Y23_Alpha(id self, SEL _cmd, double alpha, id sceneID) {
    if (gY23OrigAlpha) ((void (*)(id, SEL, double, id))gY23OrigAlpha)(self, _cmd, alpha, sceneID);
    if (!BP_OnName("y17_sbrecording")) return;
    Y23_UpdateOwnIndicator(self);
    __weak id weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{ id s = weakSelf; if (s) Y23_UpdateOwnIndicator(s); });
}
static void Y23_Hidden(id self, SEL _cmd, BOOL hidden, long long animation, id sceneID) {
    if (gY23OrigHidden) ((void (*)(id, SEL, BOOL, long long, id))gY23OrigHidden)(self, _cmd, hidden, animation, sceneID);
    if (!BP_OnName("y17_sbrecording")) return;
    Y23_UpdateOwnIndicator(self);
    __weak id weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{ id s = weakSelf; if (s) Y23_UpdateOwnIndicator(s); });
}

__attribute__((constructor)) static void Y23_Setup(void) {
    if (!BPY_BuildOK()) return;
    @autoreleasepool {
        Class c = NSClassFromString(@"SBIconController");
        int n = 0;
        if (c && class_getInstanceMethod(c, sel_registerName("_appLibraryListLayoutProviderForWindowScene:"))) {
            gY23Orig = BPX_Replace(c, "_appLibraryListLayoutProviderForWindowScene:", (IMP)Y23_ProviderForScene);
            n++;
        } else BP_Log(@"[y23] GUARD(applibrary) SBIconController _appLibraryListLayoutProviderForWindowScene: missing: not installed");
        Class sb = NSClassFromString(@"SBMainDisplaySceneLayoutStatusBarView");
        if (sb && class_getInstanceMethod(sb, sel_registerName("_applyStatusBarAlpha:toSceneWithIdentifier:")) && class_getInstanceMethod(sb, sel_registerName("_applyStatusBarHidden:withAnimation:toSceneWithIdentifier:"))) {
            gY23OrigAlpha = BPX_Replace(sb, "_applyStatusBarAlpha:toSceneWithIdentifier:", (IMP)Y23_Alpha);
            gY23OrigHidden = BPX_Replace(sb, "_applyStatusBarHidden:withAnimation:toSceneWithIdentifier:", (IMP)Y23_Hidden);
            n++;
        } else BP_Log(@"[y23] GUARD(sbrecording) SBMainDisplaySceneLayoutStatusBarView apply methods missing: not installed");
        BP_Log(@"[y23] installed %d group(s) (switches y17_applibrary, y17_sbrecording)", n);
    }
}
#pragma clang diagnostic pop
