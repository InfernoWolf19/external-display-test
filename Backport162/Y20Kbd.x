// Y20Kbd.x : delta sweep pass 2, -[SBFluidSwitcherViewController canPerformKeyboardShortcutAction:forBundleIdentifier:] (16.0 0x1c5fc1b10, 16.2 0x1c743a70c).  Setup: constructor.  Log prefix "[y20]".
//
//  y17_kbdshortcuts  The complete 16.2 decision tree, decoded from the raw disassembly of both versions (jump tables: 16.0 0x1c5fc1ff0, 20 entries for the actions 3..22, base 0x1c5fc1c64;
//                    16.2 0x1c743ac60, 18 entries for the actions 3..20, base 0x1c743a850).  Both start the same way: r = [rootModifier canPerform...:action forBundleIdentifier:bid];
//                    layout = [_liveContentOverlayCoordinator appLayoutForKeyboardFocusedScene] (ivar +0x390); bid = bid argument, else the bundle identifier of the first item of that layout;
//                    app = [[SBApplicationController sharedInstanceIfExists] applicationWithBundleIdentifier:bid]; multi = [app supportsMultiWindowLayoutsForSwitcherWindowManagementStyle:
//                    [switcherController windowManagementStyle] displayIdentity:[switcherController displayIdentity]].  Then per action (the result is r AND the rule):
//                      3                 app && [[app info] supportsMultiwindow] && [self numberOfVisibleAppLayoutsForBundleIdentifier:bid] > 0                       (same in 16.0 and 16.2)
//                      4, 5              16.0: app && supportsMultiwindow && count(_keyboardFocusableLiveAppLayoutsMatchingFocusedApp:YES) > 1.
//                                        16.2 (0x1c743a878): not Stage Manager: supportsMultiwindow([app info]) && count(list) > 1.  Stage Manager (isChamoisWindowingUIEnabled): no app / multi window test,
//                                        count(list) > 1  ||  some layout of [_rootModifier inactiveAppLayoutsReachableByKeyboardShortcut] contains an item of the bundle identifier of the
//                                        focused window (the first item of the focused layout, else of the first layout of the list) - but when the focused layout exists the inactive ones are
//                                        only looked at if the list contains a layout with that bundle identifier.
//                      6                 [[self appLayouts] bs_containsObjectPassingTest: [layout environment] == 2]                                                   (same)
//                      7 8 13 14 18      app && multi                                                                                                                  (same)
//                      11                bid argument given, or: a focused layout whose environment is 2 or 3, or whose _leafAppLayoutsToRecencyAppLayouts entry has configuration != 1  (same)
//                      12                [focused layout environment] == 1                                                                                             (same)
//                      15, 16            app && count(_keyboardFocusableLiveAppLayoutsMatchingFocusedApp:NO) > 1                                                       (same)
//                      17                NEW in 16.2: !([self appLayoutContainsAnUnoccludedMaximizedDisplayItem:layout]) (16.0: r unchanged)
//                      20                app && [connectedWindowScenes count] > 1                                                                                      (same)
//                      21, 22            REMOVED in 16.2 (16.0: more than one visible layout of the front app bundle, 0x1c5fc1d24); 16.2: r unchanged
//                      other             r
//                    Replaces the partial hook of G2B.m (which ORs the reachable layouts count for 4 5 15 16 on top of the 16.0 answer): with the switch on this replacement does not call the previous
//                    implementation (the G2B hook stays reachable through y17_kbdshortcuts off).  NEEDS NO EDIT IN G2B.m.
// Needs a device: with Stage Manager on, hardware keyboard, Command-` style window navigation items in the menu / Command-hold overlay are enabled when the app has another window or another
// window of it sits in the strip; Ctrl-Cmd-F (zoom, action 17) is disabled while the focused layout has an unoccluded maximized window.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "Y17Common.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

static IMP gY20Orig;

static id Y20_Ivar(id self, const char *name) {
    Ivar iv = class_getInstanceVariable(object_getClass(self), name);
    if (!BP_IvarIsObj(iv)) { Y17_GuardOnce("kbdshortcuts", self, name); return nil; }
    return object_getIvar(self, iv);
}
static unsigned long long Y20_Count(id arr) { return arr ? [arr count] : 0; }

static BOOL Y20_Can(id self, SEL _cmd, long long action, id bidArg) {
    if (!BP_OnName("y17_kbdshortcuts")) return gY20Orig ? ((BOOL (*)(id, SEL, long long, id))gY20Orig)(self, _cmd, action, bidArg) : NO;
    id root = BPX_Obj0(self, "rootModifier");
    BOOL r = (root && [root respondsToSelector:sel_registerName("canPerformKeyboardShortcutAction:forBundleIdentifier:")]) ? BPY_SEND(BOOL, (long long, id), root, "canPerformKeyboardShortcutAction:forBundleIdentifier:", action, bidArg) : NO;
    id layout = BPX_Obj0(Y20_Ivar(self, "_liveContentOverlayCoordinator"), "appLayoutForKeyboardFocusedScene");
    NSString *bid = bidArg ?: BPX_Obj0([BPX_Obj0(layout, "allItems") firstObject], "bundleIdentifier");
    id appCtl = BPX_Obj0((id)NSClassFromString(@"SBApplicationController"), "sharedInstanceIfExists");
    id app = bid ? BPX_Obj1(appCtl, "applicationWithBundleIdentifier:", bid) : nil;
    id sc = BPX_Obj0(self, "switcherController");
    BOOL multi = NO;
    if (app) {
        long long style = BPX_LL0(sc, "windowManagementStyle");
        id did = BPX_Obj0(sc, "displayIdentity");
        if (BPY_Responds(app, "supportsMultiWindowLayoutsForSwitcherWindowManagementStyle:displayIdentity:")) multi = BPY_SEND(BOOL, (long long, id), app, "supportsMultiWindowLayoutsForSwitcherWindowManagementStyle:displayIdentity:", style, did);
        else Y17_GuardOnce("kbdshortcuts", app, "supportsMultiWindowLayoutsForSwitcherWindowManagementStyle:displayIdentity:");
    }
    BOOL result = r;
    switch (action) {
        case 3: {
            long long n = app ? Y17_LL1(self, "numberOfVisibleAppLayoutsForBundleIdentifier:", bid) : 0;
            result = r && app && BPX_Bool0(BPX_Obj0(app, "info"), "supportsMultiwindow") && n > 0;
            break;
        }
        case 4: case 5: {
            if (!r) { result = NO; break; }
            BOOL chamois = BPX_Bool0(self, "isChamoisWindowingUIEnabled");
            if (!chamois && !BPX_Bool0(BPX_Obj0(app, "info"), "supportsMultiwindow")) { result = NO; break; }
            id list = BPY_SEND(id, (BOOL, void *), self, "_keyboardFocusableLiveAppLayoutsMatchingFocusedApp:foundAtIndex:", YES, NULL);
            unsigned long long n = Y20_Count(list);
            if (!chamois) { result = n > 1; break; }
            NSString *bid2 = layout ? BPX_Obj0([BPX_Obj0(layout, "allItems") firstObject], "bundleIdentifier") : BPX_Obj0([BPX_Obj0([list firstObject], "allItems") firstObject], "bundleIdentifier");
            BOOL look = YES;
            if (layout) {
                look = NO;
                for (id l in list) if (BPY_Responds(l, "containsItemWithBundleIdentifier:") && BPY_SEND(BOOL, (id), l, "containsItemWithBundleIdentifier:", bid2)) { look = YES; break; }
            }
            BOOL inactive = NO;
            if (look) {
                for (id l in (NSArray *)BPX_Obj0(Y20_Ivar(self, "_rootModifier"), "inactiveAppLayoutsReachableByKeyboardShortcut"))
                    if (BPY_Responds(l, "containsItemWithBundleIdentifier:") && BPY_SEND(BOOL, (id), l, "containsItemWithBundleIdentifier:", bid2)) { inactive = YES; break; }
            }
            result = n > 1 || inactive;
            break;
        }
        case 6: {
            result = NO;
            if (r) for (id l in (NSArray *)BPX_Obj0(self, "appLayouts")) if (BPX_LL0(l, "environment") == 2) { result = YES; break; }
            break;
        }
        case 7: case 8: case 13: case 14: case 18: result = r && app && multi; break;
        case 11: {
            BOOL ok;
            if (bidArg) ok = YES;
            else if (!layout) ok = NO;
            else {
                long long env = BPX_LL0(layout, "environment");
                if ((env & ~1LL) == 2) ok = YES;
                else ok = BPX_LL0(BPX_Obj1(Y20_Ivar(self, "_leafAppLayoutsToRecencyAppLayouts"), "objectForKey:", layout), "configuration") != 1;
            }
            result = r && ok;
            break;
        }
        case 12: result = r ? (BPX_LL0(layout, "environment") == 1) : NO; break;
        case 15: case 16: {
            result = NO;
            if (r && app) {
                id list = BPY_SEND(id, (BOOL, void *), self, "_keyboardFocusableLiveAppLayoutsMatchingFocusedApp:foundAtIndex:", NO, NULL);
                result = Y20_Count(list) > 1;
            }
            break;
        }
        case 17: result = r ? !BPY_SEND(BOOL, (id), self, "appLayoutContainsAnUnoccludedMaximizedDisplayItem:", layout) : NO; break;
        case 20: {
            result = NO;
            if (r && app) result = BPX_LL0(BPX_Obj0(BPX_WindowSceneManager(), "connectedWindowScenes"), "count") > 1;
            break;
        }
        default: result = r; break;
    }
    BPY_LOG(@"[y20] canPerformKeyboardShortcutAction:%lld forBundleIdentifier:%@ -> %d (root %d, app %d, multi %d)", action, bid, (int)result, (int)r, (int)(app != nil), (int)multi);
    return result;
}

__attribute__((constructor)) static void Y20_Setup(void) {
    if (!BPY_BuildOK()) return;
    @autoreleasepool {
        Class vc = NSClassFromString(@"SBFluidSwitcherViewController");
        const char *need[] = { "rootModifier", "switcherController", "numberOfVisibleAppLayoutsForBundleIdentifier:", "isChamoisWindowingUIEnabled", "_keyboardFocusableLiveAppLayoutsMatchingFocusedApp:foundAtIndex:",
            "appLayouts", "appLayoutContainsAnUnoccludedMaximizedDisplayItem:" };
        if (!vc || !class_getInstanceMethod(vc, sel_registerName("canPerformKeyboardShortcutAction:forBundleIdentifier:"))) { BP_Log(@"[y20] GUARD(kbdshortcuts) canPerformKeyboardShortcutAction:forBundleIdentifier: missing: not installed"); return; }
        for (size_t i = 0; i < sizeof need / sizeof need[0]; i++)
            if (!class_getInstanceMethod(vc, sel_registerName(need[i]))) { BP_Log(@"[y20] GUARD(kbdshortcuts) SBFluidSwitcherViewController %s missing: not installed", need[i]); return; }
        gY20Orig = BPX_Replace(vc, "canPerformKeyboardShortcutAction:forBundleIdentifier:", (IMP)Y20_Can);
        BP_Log(@"[y20] installed (switch y17_kbdshortcuts; previous implementation %p is used only with the switch off)", (void *)gY20Orig);
    }
}
#pragma clang diagnostic pop
