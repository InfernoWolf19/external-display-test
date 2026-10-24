// Y4Home.x : delta sweep family F2 (specs/DELTA-SWEEP-0.7.9.md): home screen alerts and widget editing focus.  Setup: constructor.  Log prefix "[y4]".
//
//  y4_alertscene  16.2 gives an alert item a preferred activation window scene.  -[SBAlertItem _setPreferredActivationWindowScene:] / _preferredActivationWindowScene are NEW in 16.2
//                 (the selector does not exist in 20A8372); the only setter is -[SBIconController iconManager:wantsUninstallForIcon:location:] 0x1c74a4914 (the "hide app" and
//                 "delete" confirmation items, scene = [self _sbWindowScene], the home screen's own scene) and the only reader is
//                 -[SBAlertItemPresenterWindowSceneResolver resolvedSharedModalAlertItemPresenterForAlertItem:] 0x1c74c0984 (16.0 0x1c6045050): the alert controller's scene first,
//                 else the preferred scene, else the ACTIVE display's scene.  16.0 had no preferred scene: the confirmation of a home screen icon opened on whichever display was
//                 active (the monitor after the pointer had been there).  Ported: the two accessors (associated object, weak), the setter on the two alert items while that
//                 SBIconController method runs (thread local flag; only those two creations, like 16.2), the resolver with the 16.2 order.
//  y4_widgetfocus 16.2 -iconManagerWillPresentWidgetEditing: 0x1c74a89c8 / -iconManagerDidDismissWidgetEditing: 0x1c74a8b2c: the first presentation (no add widget sheet floating dock
//                 assertion yet) asks the workspace keyboard focus controller for focus stealing for the home screen window (reason "addWidgetSheet") and makes the window key
//                 when it is not, the assertion (new ivar _addWidgetSheetKeyboardFocusAssertion, associated object here) is invalidated when the editing UI goes away.  Without it a
//                 hardware keyboard typed into whatever scene held the focus while the widget gallery search field was up.
// Needs a device: with the external display active, long press an icon on the iPad home screen, Remove App: the confirmation appears on the iPad; widget gallery: the search
// field takes hardware keyboard input.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "BPY.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

@interface Y4WeakScene : NSObject { @public __weak id scene; } @end
@implementation Y4WeakScene @end

static const void *kY4PrefScene = &kY4PrefScene;
static const void *kY4FocusAssertion = &kY4FocusAssertion;
static __thread void *tY4PrefScene;            // unretained: the scene given to alert items created while -iconManager:wantsUninstallForIcon:location: runs
static IMP gY4OrigUninstall, gY4OrigHideInit, gY4OrigDelInit, gY4OrigResolve, gY4OrigWillPresent, gY4OrigDidDismiss;

// -[SBAlertItem _setPreferredActivationWindowScene:] / -_preferredActivationWindowScene (new in 16.2)
static void Y4_SetPref(id self, SEL _cmd, id scene) {
    Y4WeakScene *w = [Y4WeakScene new];
    w->scene = scene;
    objc_setAssociatedObject(self, kY4PrefScene, w, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static id Y4_GetPref(id self, SEL _cmd) {
    Y4WeakScene *w = objc_getAssociatedObject(self, kY4PrefScene);
    return w ? w->scene : nil;
}

// -[SBIconController iconManager:wantsUninstallForIcon:location:]: the two alert items made inside get the home screen's scene
static void Y4_Uninstall(id self, SEL _cmd, id mgr, id icon, id location) {
    void *prev = tY4PrefScene;
    id scene = BP_OnName("y4_alertscene") ? BPX_Obj0(self, "_sbWindowScene") : nil;
    tY4PrefScene = scene ? (__bridge void *)scene : NULL;
    if (gY4OrigUninstall) ((void (*)(id, SEL, id, id, id))gY4OrigUninstall)(self, _cmd, mgr, icon, location);
    tY4PrefScene = prev;
}
static id Y4_ApplyPref(id item) {
    void *p = tY4PrefScene;
    if (item && p) {
        id scene = (__bridge id)p;
        Y4_SetPref(item, NULL, scene);
        BPY_LOG(@"[y4] alert item %p prefers the scene %p", (__bridge void *)item, (__bridge void *)scene);
    }
    return item;
}
static id Y4_HideInit(id self, SEL _cmd, id icon, id location) {
    id r = gY4OrigHideInit ? ((id (*)(id, SEL, id, id))gY4OrigHideInit)(self, _cmd, icon, location) : nil;
    return Y4_ApplyPref(r);
}
static id Y4_DelInit(id self, SEL _cmd, id icon, id location) {
    id r = gY4OrigDelInit ? ((id (*)(id, SEL, id, id))gY4OrigDelInit)(self, _cmd, icon, location) : nil;
    return Y4_ApplyPref(r);
}

// -[SBAlertItemPresenterWindowSceneResolver resolvedSharedModalAlertItemPresenterForAlertItem:]  16.2 0x1c74c0984
static id Y4_Resolve(id self, SEL _cmd, id item) {
    if (!BP_OnName("y4_alertscene"))
        return gY4OrigResolve ? ((id (*)(id, SEL, id))gY4OrigResolve)(self, _cmd, item) : nil;
    id scene = BPX_Obj0(BPX_Obj0(item, "alertController"), "_sbWindowScene");
    if (!scene) {
        id pref = BPX_Obj0(item, "_preferredActivationWindowScene");
        Class ws = NSClassFromString(@"SBWindowScene");
        scene = (ws && [pref isKindOfClass:ws]) ? pref : nil;
    }
    id presenters = BPX_Obj0(self, "modalAlertPresenters");
    if (scene) {
        id p = [presenters objectForKey:scene];
        if (p) return p;
    }
    return [presenters objectForKey:BPX_Obj0(BPX_Obj0(self, "windowSceneManager"), "activeDisplayWindowScene")];
}

// ---- widget editing keyboard focus
static const char *kY4DockIvar = "_addWidgetSheetFloatingDockBehaviorAssertion";
static void Y4_WillPresent(id self, SEL _cmd, id mgr) {
    if (BP_OnName("y4_widgetfocus") && !BPX_IvarObj(self, kY4DockIvar)) {          // first presentation (the 16.2 body skips everything when the dock assertion exists)
        id window = BPX_Obj0(BPX_Obj0(self, "view"), "window");
        if (window && !objc_getAssociatedObject(self, kY4FocusAssertion)) {
            id fc = BPX_Obj0(BPX_MainWorkspace(), "keyboardFocusController");
            id a = BPX_Obj2(fc, "requestFocusStealingForSpringBoardWindow:forReason:", window, @"addWidgetSheet");
            if (a) objc_setAssociatedObject(self, kY4FocusAssertion, a, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            BPY_LOG(@"[y4] widget editing: focus stealing requested for the home screen window %p (assertion %p)", (__bridge void *)window, (__bridge void *)a);
        }
        if (window && !BPX_Bool0(window, "isKeyWindow")) ((void (*)(id, SEL))objc_msgSend)(window, sel_registerName("makeKeyWindow"));
    }
    if (gY4OrigWillPresent) ((void (*)(id, SEL, id))gY4OrigWillPresent)(self, _cmd, mgr);
}
static void Y4_DidDismiss(id self, SEL _cmd, id mgr) {
    if (gY4OrigDidDismiss) ((void (*)(id, SEL, id))gY4OrigDidDismiss)(self, _cmd, mgr);
    id a = objc_getAssociatedObject(self, kY4FocusAssertion);
    if (a) {
        objc_setAssociatedObject(self, kY4FocusAssertion, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        ((void (*)(id, SEL))objc_msgSend)(a, sel_registerName("invalidate"));
        BPY_LOG(@"[y4] widget editing: focus stealing assertion %p invalidated", (__bridge void *)a);
    }
}

__attribute__((constructor)) static void Y4_Setup(void) {
    if (!BPY_BuildOK()) return;
    @autoreleasepool {
        Class ic = NSClassFromString(@"SBIconController"), ai = NSClassFromString(@"SBAlertItem"), rs = NSClassFromString(@"SBAlertItemPresenterWindowSceneResolver");
        Class hide = NSClassFromString(@"SBHideAppIconAlertItem"), del = NSClassFromString(@"SBDeleteNonAppIconAlertItem");
        if (!ic || !ai || !rs || !hide || !del) { BP_Log(@"[y4] NOT installed (class missing)"); return; }
        if (!class_getInstanceMethod(ai, sel_registerName("_setPreferredActivationWindowScene:"))) {
            class_addMethod(ai, sel_registerName("_setPreferredActivationWindowScene:"), (IMP)Y4_SetPref, "v24@0:8@16");
            class_addMethod(ai, sel_registerName("_preferredActivationWindowScene"), (IMP)Y4_GetPref, "@16@0:8");
        }
        gY4OrigUninstall = BPX_Replace(ic, "iconManager:wantsUninstallForIcon:location:", (IMP)Y4_Uninstall);
        gY4OrigHideInit = BPX_Replace(hide, "initWithIcon:location:", (IMP)Y4_HideInit);
        gY4OrigDelInit = BPX_Replace(del, "initWithIcon:location:", (IMP)Y4_DelInit);
        gY4OrigResolve = BPX_Replace(rs, "resolvedSharedModalAlertItemPresenterForAlertItem:", (IMP)Y4_Resolve);
        gY4OrigWillPresent = BPX_Replace(ic, "iconManagerWillPresentWidgetEditing:", (IMP)Y4_WillPresent);
        gY4OrigDidDismiss = BPX_Replace(ic, "iconManagerDidDismissWidgetEditing:", (IMP)Y4_DidDismiss);
        BP_Log(@"[y4] installed (switches y4_alertscene, y4_widgetfocus)");
    }
}
#pragma clang diagnostic pop
