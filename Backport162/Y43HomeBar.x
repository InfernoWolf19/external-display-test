// Y43HomeBar.x : DELIBERATE DEVIATION from 16.2 (requested by the user): the home bar and the Stage Manager corner resize marks of an APP window hide themselves after the home grabber
// auto hide delay (SBFHomeGrabberSettings autoHideTime, 2.0 s without touch) and come back on a tap, in EVERY app, not only in apps that ask for it (video players).  Stock 16.0 and 16.2 are
// identical here: the single input is -[SBFullScreenSwitcherLiveContentOverlayCoordinator wantsHomeAffordanceAutoHideForAppLayout:] (16.0 0x1c605071c, 16.2 0x1c74cc648), which answers
// [[handle of the primary item] isAutoHideEnabledForHomeAffordance] = the app's own prefersHomeIndicatorAutoHidden, and NO for every item that is not an app.  Its consumers are unchanged and
// do the rest: -[SBFluidSwitcherViewController _updateEdgeProtectAndAutoHideForHomeAffordancesInAppLayout:...] (turnOnAutoHideWithInitialDelay: on the home grabber, skipped while an app has
// edge protect on = the app keeps its bar when it asks for the home gesture to be protected), G2C.x -_updateAutoHideForItemContainer:appLayout: (the corner marks, setAutoHideAffordance:).
//   Hook: the answer of that method is YES when the stock answer is NO and the layout's primary item is an app (item type 0 with a bundle identifier).  Nothing else is changed: the top
//   affordance ("..." menu) reads the scene handle flag directly and is not touched; a layout that is not an app keeps NO.
// Switch homebar_autohide (default ON, kill file Backport162.off.homebar_autohide).  Always-on ANOMALY homebar-autohide once per app: "forced auto hide for <bundle>" so the log shows when it applies.
// Not a 16.2 port: it is listed in the README as a deviation.  Log prefix "[y43]".

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "Y17Common.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

static BOOL Y43_On(void) { return BP_OnName("homebar_autohide"); }
static NSMutableDictionary *gY43Orig;                       // class name -> NSValue(IMP) of the stock method
static NSMutableSet *gY43Seen;

static id Y43_Send0(id o, const char *sel) { SEL s = sel_registerName(sel); return (o && [o respondsToSelector:s]) ? ((id (*)(id, SEL))objc_msgSend)(o, s) : nil; }

static BOOL Y43_IsAppLayout(id layout, NSString **bundleOut) {
    SEL it = sel_registerName("itemForLayoutRole:");
    if (!layout || ![layout respondsToSelector:it]) return NO;
    id item = ((id (*)(id, SEL, long long))objc_msgSend)(layout, it, 1);                  // SBLayoutRolePrimary = 1
    if (!item || ![item respondsToSelector:sel_registerName("type")]) return NO;
    long long type = ((long long (*)(id, SEL))objc_msgSend)(item, sel_registerName("type"));
    id bid = Y43_Send0(item, "bundleIdentifier");
    if (type != 0 || ![bid isKindOfClass:[NSString class]] || ![(NSString *)bid length]) return NO;   // 0 = app (16.2 0x1c74cc648 compares the same item type)
    if (bundleOut) *bundleOut = bid;
    return YES;
}

static BOOL Y43_Wants(id self, SEL _cmd, id layout) {
    IMP orig = [[gY43Orig objectForKey:NSStringFromClass([self class])] pointerValue];
    if (!orig) for (Class c = [self class]; c && !orig; c = class_getSuperclass(c)) orig = [[gY43Orig objectForKey:NSStringFromClass(c)] pointerValue];
    BOOL stock = orig ? ((BOOL (*)(id, SEL, id))orig)(self, _cmd, layout) : NO;
    if (stock || !Y43_On()) return stock;
    NSString *bid = nil;
    if (!Y43_IsAppLayout(layout, &bid)) return NO;
    @synchronized (gY43Seen) {
        if (![gY43Seen containsObject:bid]) { [gY43Seen addObject:bid]; BP_Anomaly("homebar-autohide", @"forced auto hide of the home bar and corner marks for %@ (the app did not ask for it; deviation, kill file Backport162.off.homebar_autohide)", bid); }
    }
    return YES;
}

__attribute__((constructor)) static void Y43_Setup(void) {
    if (!BPY_BuildOK()) return;
    @autoreleasepool {
        gY43Orig = [NSMutableDictionary dictionary];
        gY43Seen = [NSMutableSet set];
        NSMutableArray *missing = [NSMutableArray array];
        const char *names[] = { "SBFullScreenSwitcherLiveContentOverlayCoordinator", "SBShelfLiveContentOverlayCoordinator" };
        SEL want = sel_registerName("wantsHomeAffordanceAutoHideForAppLayout:");
        int n = 0;
        for (size_t i = 0; i < sizeof names / sizeof names[0]; i++) {
            Class c = objc_getClass(names[i]);
            if (!c || !class_getInstanceMethod(c, want)) { [missing addObject:[NSString stringWithFormat:@"-[%s wantsHomeAffordanceAutoHideForAppLayout:]", names[i]]]; continue; }
            Method m = class_getInstanceMethod(c, want);
            IMP orig = method_getImplementation(m);
            [gY43Orig setObject:[NSValue valueWithPointer:(void *)orig] forKey:NSStringFromClass(c)];
            class_replaceMethod(c, want, (IMP)Y43_Wants, method_getTypeEncoding(m));
            n++;
        }
        if (!n) { BP_Anomaly("y43-install", @"[y43] homebar_autohide NOT installed, needs: %@", [missing componentsJoinedByString:@", "]); return; }
        if ([missing count]) BP_Anomaly("y43-install", @"[y43] homebar_autohide installed on %d coordinator(s); missing: %@", n, [missing componentsJoinedByString:@", "]);
        BP_Log(@"[y43] installed homebar_autohide on %d coordinator(s)", n);
    }
}
#pragma clang diagnostic pop
