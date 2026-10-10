// group3b-reconstruct.hooks.m
//
// DRAFT (Logos, rename to .xm / paste into the tweak). Reconstruction of everything that group3-plumbing.md called NOT PORTABLE
// or inert, for iPadOS 16.0 (20A8372) from the 16.2 (20C65) disassembly. Behaviour is specified in group3b-reconstruct.md
// (section numbers in the comments refer to it). Every piece is tagged DONE or UNSURE:<what to check on a device>.
//
// Integration (do not paste blindly):
//   * One switch per piece: <jbroot>/tmp/Backport162.off[.<name>] turns it off (BP_G3B_On(name)). Names: g3b_banner, g3b_menu, ...
//   * Call BP_G3B_Setup() from the %ctor after the build check (it %init()s every group below).
//   * Compile with ARC (-fobjc-arc), -Wall -Werror.  No ivar offset is hard coded: ivars are found by name.
//   * Needs group3-plumbing.hooks.m only for the kBPG3WMStyleNote poster (g3switcher); everything else here is self-contained.
//
// Safety rules (same as groups 3/4): respondsToSelector guards on every private call, nothing dereferences nil, ivars through
// class_getInstanceVariable/ivar_getOffset by name, messages with non-id signatures through objc_msgSend casts, %orig on its own line.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <string.h>
#import <dlfcn.h>
#import <unistd.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wunused-variable"

#import "BP.h"

// INTEGRATION: interface declarations for the hooked classes (Logos only emits @class, ARC needs a visible @interface to message them)
@interface SBFullKeyboardAccessUISceneController : NSObject @end
@interface SBVoiceControlUISceneController : NSObject @end
@interface SBAssistiveTouchUISceneController : NSObject @end
@interface SBAccessibilityUIServerUISceneController : NSObject @end
@interface SBExternalDisplayWindowSceneDelegate : NSObject @end
@interface SBEmbeddedDisplayWindowSceneDelegate : NSObject @end
@interface SBTraitsExternalDisplayRolesAndDefaultPoliciesProvider : NSObject @end
@interface SBTraitsEmbeddedDisplayRolesAndDefaultPoliciesProvider : NSObject @end
@interface SBMainDisplaySceneManager : NSObject @end
@interface SBSystemShellExternalDisplaySceneManager : NSObject @end
@interface SBMedusaHostedKeyboardWindow : NSObject @end
// END INTEGRATION interfaces

// per-piece switch: on by default, off when <jbroot>/tmp/Backport162.off or Backport162.off.<name> exists
static BOOL BP_G3B_On(const char *name) { return BP_OnName(name); }     // INTEGRATION: shared switches (BP.h)

// ------------------------------------------------------------------------------------------------ generic helpers
static id BP_G3B_Ivar(id obj, const char *name) {                       // object ivar by name, nil if absent / not an object
    if (!obj) return nil;
    Ivar iv = class_getInstanceVariable([obj class], name);
    if (!iv) return nil;
    const char *enc = ivar_getTypeEncoding(iv);
    if (!enc || enc[0] != '@') return nil;
    return object_getIvar(obj, iv);
}
static BOOL BP_G3B_SetIvar(id obj, const char *name, id val) {          // strong object ivar (object_setIvar retains)
    if (!obj) return NO;
    Ivar iv = class_getInstanceVariable([obj class], name);
    if (!iv) return NO;
    const char *enc = ivar_getTypeEncoding(iv);
    if (!enc || enc[0] != '@') return NO;
    object_setIvar(obj, iv, val);
    return YES;
}
static BOOL BP_G3B_ScalarIvar(id obj, const char *name, long long *out) {   // integer/BOOL ivar by name
    Ivar iv = obj ? class_getInstanceVariable([obj class], name) : NULL;
    if (!iv) return NO;
    const char *enc = ivar_getTypeEncoding(iv);
    if (!enc) return NO;
    char *p = (char *)(__bridge void *)obj + ivar_getOffset(iv);
    switch (enc[0]) {
        case 'B': case 'c': case 'C': *out = *(BOOL *)p; return YES;
        case 'i': *out = *(int *)p; return YES;
        case 'I': *out = *(unsigned int *)p; return YES;
        case 'q': case 'l': *out = *(long long *)p; return YES;
        case 'Q': case 'L': *out = (long long)*(unsigned long long *)p; return YES;
        default: return NO;
    }
}
static id BP_G3B_App(void) {
    Class c = NSClassFromString(@"UIApplication");
    return [c respondsToSelector:@selector(sharedApplication)] ? [c sharedApplication] : nil;
}
static id BP_G3B_Send0(id obj, SEL s) {                                  // [obj s] for id-returning no-arg private selectors
    return (obj && [obj respondsToSelector:s]) ? ((id (*)(id, SEL))objc_msgSend)(obj, s) : nil;
}
static long long BP_G3B_SendLL(id obj, SEL s) {
    return (obj && [obj respondsToSelector:s]) ? ((long long (*)(id, SEL))objc_msgSend)(obj, s) : 0;
}

// weak association box
@interface BPG3BWeakBox : NSObject @property (nonatomic, weak) id obj; @end
@implementation BPG3BWeakBox @end
static void BP_G3B_SetWeak(id owner, const void *key, id obj) {
    if (!owner) return;
    if (!obj) { objc_setAssociatedObject(owner, key, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); return; }
    BPG3BWeakBox *b = [BPG3BWeakBox new]; b.obj = obj;
    objc_setAssociatedObject(owner, key, b, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static id BP_G3B_GetWeak(id owner, const void *key) { return owner ? [(BPG3BWeakBox *)objc_getAssociatedObject(owner, key) obj] : nil; }

// classes we hook (declaration only)
@interface SBMedusaBannerViewController : UIViewController @end
@interface SBSwitcherController : NSObject @end
@interface SBMedusaDecoratedDeviceApplicationSceneViewController : UIViewController @end
@interface SpringBoard : UIApplication @end

// ================================================================================================ ITEM 7a: toasts -> system banner
// (spec section 7.1)  DONE  (strings: UNSURE:wording, see below)
@interface NSObject (BPG3BBanner)
- (id)_currentLayoutState;
- (long long)interfaceOrientation;
- (long long)peekConfiguration;
- (id)initWithType:(long long)type orientation:(long long)o peekConfiguration:(long long)p;
- (id)bannerManager;
- (void)scheduleWithFireInterval:(double)fire leewayInterval:(double)leeway queue:(dispatch_queue_t)q handler:(id)h;
- (void)cancel;
- (void)invalidate;
- (id)initWithIdentifier:(NSString *)i;
- (BOOL)_shouldShowSplitViewNotSupportedMessageForLayoutStateTransitionContext:(id)ctx;
- (BOOL)_shouldShowMultipleWindowsNotSupportedMessageForLayoutStateTransitionContext:(id)ctx;
- (void)_bpPresentMedusaBanner:(long long)type fireInterval:(double)fire dismissInterval:(double)dismiss;
- (void)_bpDismissMedusaBanner;
@end

static char kBPG3BDismissTimer;

static NSString *BP_G3B_Localized(NSString *key16_2, NSString *key16_0, NSString *english) {
    NSBundle *b = [NSBundle mainBundle];
    NSString *s = [b localizedStringForKey:key16_2 value:@"" table:@"SpringBoard"];
    if (s.length && ![s isEqualToString:key16_2]) return s;                       // a 16.2-style strings table is installed
    s = [b localizedStringForKey:key16_0 value:@"" table:@"SpringBoard"];         // 16.0 key with the same wording, localized
    if (s.length && ![s isEqualToString:key16_0]) return s;
    return english;
}

%group G3B_Banner

%hook SBMedusaBannerViewController

// 16.2 0x1c782418c (+77 insns vs 16.0 0x1c637cd80): types 2 and 3 (error banners). 16.0 treats every type >= 1 as "slide over".
- (id)_bannerView {
    long long type = 0;
    if (!BP_G3B_On("g3b_banner") || !BP_G3B_ScalarIvar(self, "_type", &type) || (type != 2 && type != 3)) return %orig;
    id pill = BP_G3B_Ivar(self, "_pillView");
    if (pill) return pill;
    Class pillC = NSClassFromString(@"PLPillView"), itemC = NSClassFromString(@"PLPillContentItem");
    if (!pillC || !itemC) return %orig;
    NSString *symbol = (type == 2) ? @"rectangle.split.2x1.slash" : @"rectangle.on.rectangle.slash";
    NSString *title = (type == 2)
        ? BP_G3B_Localized(@"MEDUSA_BANNER_ERROR_TITLE_SPLIT_VIEW", @"TOP_AFFORDANCE_ERROR_TITLE_SPLIT_VIEW", @"Split View")
        : BP_G3B_Localized(@"MEDUSA_BANNER_ERROR_TITLE_MULTIPLE_WINDOWS", @"TOP_AFFORDANCE_ERROR_TITLE_MULTIPLE_WINDOWS", @"Multiple Windows");
    NSString *subtitle = BP_G3B_Localized(@"MEDUSA_BANNER_ERROR_SUBTITLE", @"TOP_AFFORDANCE_ERROR_SUBTITLE", @"Not Supported");
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:15.0 weight:UIImageSymbolWeightMedium];
    UIImage *img = [[UIImage systemImageNamed:symbol withConfiguration:cfg] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    UIImageView *iv = [[UIImageView alloc] initWithImage:img];
    UIView *trailing = [[UIView alloc] initWithFrame:iv.bounds];                   // same size spacer on the other side, as 16.2
    id p = ((id (*)(id, SEL, id, id))objc_msgSend)([pillC alloc], NSSelectorFromString(@"initWithLeadingAccessoryView:trailingAccessoryView:"), iv, trailing);
    if (!p) return %orig;
    BP_G3B_SetIvar(self, "_pillView", p);
    if ([p respondsToSelector:@selector(setTintColor:)]) [(UIView *)p setTintColor:[UIColor labelColor]];
    SEL initItem = NSSelectorFromString(@"initWithText:style:");
    id i1 = ((id (*)(id, SEL, id, long long))objc_msgSend)([itemC alloc], initItem, title, 1);
    id i2 = ((id (*)(id, SEL, id, long long))objc_msgSend)([itemC alloc], initItem, subtitle, 2);
    SEL setItems = NSSelectorFromString(@"setCenterContentItems:");
    if (i1 && i2 && [p respondsToSelector:setItems]) ((void (*)(id, SEL, id))objc_msgSend)(p, setItems, @[i1, i2]);
    return p;
}
%end

%hook SBSwitcherController

// 16.2 0x1c7605b58 -[SBSwitcherController _presentMedusaBanner:fireInterval:dismissInterval:] (generalises _presentMedusaEducationBanner)
%new
- (void)_bpPresentMedusaBanner:(long long)type fireInterval:(double)fire dismissInterval:(double)dismiss {
    Class bannerC = NSClassFromString(@"SBMedusaBannerViewController"), timerC = NSClassFromString(@"BSAbsoluteMachTimer");
    id ls = BP_G3B_Send0(self, NSSelectorFromString(@"_currentLayoutState"));
    if (!bannerC || !timerC || !ls) return;
    id banner = ((id (*)(id, SEL, long long, long long, long long))objc_msgSend)([bannerC alloc],
        NSSelectorFromString(@"initWithType:orientation:peekConfiguration:"), type, BP_G3B_SendLL(ls, @selector(interfaceOrientation)),
        BP_G3B_SendLL(ls, NSSelectorFromString(@"peekConfiguration")));
    if (!banner || !BP_G3B_SetIvar(self, "_medusaBannerViewController", banner)) return;
    if (dismiss > 0 && !objc_getAssociatedObject(self, &kBPG3BDismissTimer)) {
        id t = ((id (*)(id, SEL, id))objc_msgSend)([timerC alloc], NSSelectorFromString(@"initWithIdentifier:"), @"SBMainSwitcherCoordinator.medusaBannerDismissTimer");
        if (t) objc_setAssociatedObject(self, &kBPG3BDismissTimer, t, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    id present = BP_G3B_Ivar(self, "_medusaBannerPresentTimer");
    if (!present) {
        present = ((id (*)(id, SEL, id))objc_msgSend)([timerC alloc], NSSelectorFromString(@"initWithIdentifier:"), @"SBMainSwitcherCoordinator.medusaBannerPresentTimer");
        BP_G3B_SetIvar(self, "_medusaBannerPresentTimer", present);
    }
    if (![present respondsToSelector:@selector(cancel)]) return;
    [present cancel];
    __weak id weakSelf = self;
    SEL sched = NSSelectorFromString(@"scheduleWithFireInterval:leewayInterval:queue:handler:");
    void (^fireBlock)(id) = ^(id timer) {
        (void)timer;
        id me = weakSelf; if (!me) return;
        id pt = BP_G3B_Ivar(me, "_medusaBannerPresentTimer");
        if ([pt respondsToSelector:@selector(invalidate)]) [pt invalidate];
        BP_G3B_SetIvar(me, "_medusaBannerPresentTimer", nil);
        id bm = BP_G3B_Send0(BP_G3B_App(), NSSelectorFromString(@"bannerManager"));
        id bn = BP_G3B_Ivar(me, "_medusaBannerViewController");
        SEL post = NSSelectorFromString(@"postPresentable:withOptions:userInfo:error:");
        if (bn && [bm respondsToSelector:post]) ((id (*)(id, SEL, id, unsigned long long, id, id *))objc_msgSend)(bm, post, bn, 1, nil, NULL);
        id dt = objc_getAssociatedObject(me, &kBPG3BDismissTimer);
        if (dismiss > 0 && [dt respondsToSelector:@selector(cancel)]) {
            [dt cancel];
            void (^dismissBlock)(id) = ^(id t2) { (void)t2; id m2 = weakSelf; if (m2) [m2 _bpDismissMedusaBanner]; };
            if ([dt respondsToSelector:sched]) ((void (*)(id, SEL, double, double, dispatch_queue_t, id))objc_msgSend)(dt, sched, dismiss, 0.05, dispatch_get_main_queue(), dismissBlock);
        }
    };
    if ([present respondsToSelector:sched]) ((void (*)(id, SEL, double, double, dispatch_queue_t, id))objc_msgSend)(present, sched, fire, 0.05, dispatch_get_main_queue(), fireBlock);
}

// 16.2 0x1c7605f14 -[SBSwitcherController _dismissMedusaBanner]
%new
- (void)_bpDismissMedusaBanner {
    id pt = BP_G3B_Ivar(self, "_medusaBannerPresentTimer");
    if ([pt respondsToSelector:@selector(invalidate)]) [pt invalidate];
    BP_G3B_SetIvar(self, "_medusaBannerPresentTimer", nil);
    id dt = objc_getAssociatedObject(self, &kBPG3BDismissTimer);
    if ([dt respondsToSelector:@selector(invalidate)]) [dt invalidate];
    objc_setAssociatedObject(self, &kBPG3BDismissTimer, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    id bm = BP_G3B_Send0(BP_G3B_App(), NSSelectorFromString(@"bannerManager"));
    id bn = BP_G3B_Ivar(self, "_medusaBannerViewController");
    Class idC = NSClassFromString(@"BNPresentableIdentification");
    SEL uid = NSSelectorFromString(@"uniqueIdentificationForPresentable:");
    SEL revoke = NSSelectorFromString(@"revokePresentablesWithIdentification:reason:options:userInfo:error:");
    if (bn && bm && [idC respondsToSelector:uid] && [bm respondsToSelector:revoke]) {
        id ident = ((id (*)(id, SEL, id))objc_msgSend)(idC, uid, bn);
        if (ident) ((id (*)(id, SEL, id, id, unsigned long long, id, id *))objc_msgSend)(bm, revoke, ident, @"Dismiss Medusa Education Banner", 0, nil, NULL);
    }
}
%end

%hook SBMedusaDecoratedDeviceApplicationSceneViewController

// 16.0 0x1c632fc04 showed one of three toasts in the window's top affordance; 16.2 moved the decision to
// SBFullScreenSwitcherLiveContentOverlayCoordinator (0x1c74cc740) which shows system banners type 2/3 for 1.5 s and drops the
// "not available yet" message. The two predicates are byte-for-byte the same logic in both builds (diffed), so the 16.0 ones are reused.
- (void)_presentTransientErrorMessageIfNeededForLayoutStateTransitionContext:(id)ctx {
    if (!BP_G3B_On("g3b_banner")) {
        %orig;
        return;
    }
    id vc = self;
    id handle = BP_G3B_Ivar(vc, "_deviceApplicationSceneHandle");
    id scene = BP_G3B_Send0(handle, NSSelectorFromString(@"_windowScene"));
    id sc = BP_G3B_Send0(scene, NSSelectorFromString(@"switcherController"));
    if (!sc || ![sc respondsToSelector:@selector(_bpPresentMedusaBanner:fireInterval:dismissInterval:)]) {
        %orig;
        return;
    }
    if ([self _shouldShowSplitViewNotSupportedMessageForLayoutStateTransitionContext:ctx]) [sc _bpPresentMedusaBanner:2 fireInterval:0 dismissInterval:1.5];
    else if ([self _shouldShowMultipleWindowsNotSupportedMessageForLayoutStateTransitionContext:ctx]) [sc _bpPresentMedusaBanner:3 fireInterval:0 dismissInterval:1.5];
}
%end

%end // G3B_Banner

// ================================================================================================ ITEM 7b: Stage Manager menu loses "Next/Previous App Window" (action 0x15/0x16)
// (spec section 7.2)  DONE
static __thread BOOL gBPG3BInBuildMenu;

%group G3B_Menu

%hook SpringBoard
- (void)buildMenuWithBuilder:(id)builder {
    gBPG3BInBuildMenu = BP_G3B_On("g3b_menu");
    %orig;
    gBPG3BInBuildMenu = NO;
}
%end

%hook UIMenu
// 16.0 builds the STAGE_MANAGER_MENU_TITLE menu with +menuWithTitle:children: (0x1c5ee3b88); the 16.2 children list simply lacks the
// _handleNavigateAppWindowsInStripKeyShortcut: command (cmd+opt+` with shift alternate). Filter it out while buildMenuWithBuilder: runs.
+ (id)menuWithTitle:(NSString *)title children:(NSArray *)children {
    if (gBPG3BInBuildMenu && [children count]) {
        SEL strip = NSSelectorFromString(@"_handleNavigateAppWindowsInStripKeyShortcut:");
        NSMutableArray *kept = nil;
        for (id c in children) {
            BOOL drop = [c respondsToSelector:@selector(action)] && ((SEL (*)(id, SEL))objc_msgSend)(c, @selector(action)) == strip;
            if (drop && !kept) {
                kept = [NSMutableArray arrayWithCapacity:children.count];
                for (id k in children) { if (k == c) break; [kept addObject:k]; }
            } else if (kept && !drop) {
                [kept addObject:c];
            }
        }
        if (kept) return %orig(title, kept);
    }
    return %orig;
}
%end
%end // G3B_Menu


// ================================================================================================ ITEM 4: privacy preflight (replacement)
// (spec section 4)  DONE (replacement). PrivacyDisclosureCore / com.apple.PDUIApp do not exist in 16.0, so the gate is never enforced;
// the 16.2 decision rule is reproduced for the opt-in diagnostic log only.
static BOOL BP_G3B_OptIn(const char *name) { return BP_OptInName(name); }
static BOOL BP_G3B_PreflightFeatureEnabled(void) {       // +[PDCPreflightManager isPreflightFeatureEnabled] 0x20e63dea0
    static BOOL result; static dispatch_once_t once;
    dispatch_once(&once, ^{
        BOOL (*feature)(const char *, const char *) = (BOOL (*)(const char *, const char *))dlsym(RTLD_DEFAULT, "os_feature_enabled_impl");
        BOOL (*mg)(CFStringRef) = (BOOL (*)(CFStringRef))dlsym(RTLD_DEFAULT, "MGGetBoolAnswer");
        BOOL (*ctGreen)(void) = (BOOL (*)(void))dlsym(RTLD_DEFAULT, "ct_green_tea_logging_enabled");
        BOOL preflight = feature ? feature("PrivacyDisclosure", "preflight") : NO;
        BOOL allRegions = feature ? feature("PrivacyDisclosure", "preflightInAllRegions") : NO;
        BOOL greenTea = mg ? mg(CFSTR("green-tea")) : NO;
        BOOL ctLog = ctGreen ? ctGreen() : NO;
        result = (allRegions || greenTea) && (preflight || ctLog);
    });
    return result;
}
static NSString *BP_G3B_ConsentedVersion(NSString *bundleID) {   // PDCFileBackedConsentStore, file per bundle id
    if (!bundleID.length) return nil;
    NSString *p = [@"/var/mobile/Library/com.apple.PrivacyDisclosure/consents/" stringByAppendingString:bundleID];
    return [NSString stringWithContentsOfFile:p encoding:NSUTF8StringEncoding error:NULL];
}
static BOOL BP_G3B_PreflightRequiredForBundle(NSString *bundleID) {   // -[PDCPreflightManager _requiresPreflightForApplicationRecord:] 0x20e63dc00
    if (!bundleID.length || !BP_G3B_PreflightFeatureEnabled()) return NO;
    Class lsr = NSClassFromString(@"LSApplicationRecord");
    id rec = nil;
    if (lsr && [lsr instancesRespondToSelector:NSSelectorFromString(@"initWithBundleIdentifier:allowPlaceholder:error:")])
        rec = ((id (*)(id, SEL, id, BOOL, id *))objc_msgSend)([lsr alloc], NSSelectorFromString(@"initWithBundleIdentifier:allowPlaceholder:error:"), bundleID, NO, NULL);
    NSString *v = [rec respondsToSelector:NSSelectorFromString(@"regulatoryPrivacyDisclosureVersion")]
        ? ((id (*)(id, SEL))objc_msgSend)(rec, NSSelectorFromString(@"regulatoryPrivacyDisclosureVersion")) : nil;
    if (!v) return NO;
    return ![v isEqual:BP_G3B_ConsentedVersion(bundleID)];
}

@interface SBApplicationSceneUpdateTransaction : NSObject @end
%group G3B_Preflight
%hook SBApplicationSceneUpdateTransaction
- (id)initWithApplicationSceneEntity:(id)entity transitionRequest:(id)request {
    id me = %orig;
    if (me && BP_G3B_OptIn("g3b_preflightlog")) {
        id handle = BP_G3B_Send0(entity, NSSelectorFromString(@"sceneHandle"));
        id app = BP_G3B_Send0(handle, NSSelectorFromString(@"application"));
        NSString *bid = BP_G3B_Send0(app, NSSelectorFromString(@"bundleIdentifier"));
        if ([bid isKindOfClass:[NSString class]] && BP_G3B_PreflightRequiredForBundle(bid))
            BP_Log(@"preflight: 16.2 would gate launch of %@ (not enforced on 16.0)", bid);
    }
    return me;
}
%end
%end // G3B_Preflight


// ================================================================================================ ITEM 6: traits roles (AX split)
// (spec section 6)  DONE, OPT-IN (Backport162.on.g3b_axroles): behaviour-neutral on 16.0. EyedropperUI / MomentsUI have no 16.0 consumer (skipped).
static NSString *const kBPRoleAXAssistiveTouch = @"SBTraitsParticipantRoleAXAssistiveTouchUI";
static NSString *const kBPRoleAXFullKeyboard   = @"SBTraitsParticipantRoleAXFullKeyboardUI";
static NSString *const kBPRoleAXVoiceControl   = @"SBTraitsParticipantRoleAXVoiceControlUI";
static NSString *const kBPRoleAXUIServer       = @"SBTraitsParticipantRoleAXUIServer";

static id BP_G3B_SetupInfoWithRole(id info, NSString *role) {             // replace the traitsRole entry of a scene controller's +_setupInfo
    if (![info isKindOfClass:[NSDictionary class]] || !role) return info;
    NSMutableDictionary *m = [info mutableCopy];
    m[@"traitsRole"] = role;
    return m;
}
static id BP_G3B_AppendRoles(id coll) {                                  // keep kind (array / set / ordered set), cache per original object
    static NSMapTable *cache; static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSMapTable weakToStrongObjectsMapTable]; });
    if (!coll) return coll;
    @synchronized (cache) {
        id hit = [cache objectForKey:coll];
        if (hit) return hit;
        NSArray *add = @[kBPRoleAXAssistiveTouch, kBPRoleAXFullKeyboard, kBPRoleAXVoiceControl, kBPRoleAXUIServer];
        id out = nil;
        if ([coll isKindOfClass:[NSOrderedSet class]]) { NSMutableOrderedSet *m = [coll mutableCopy]; [m addObjectsFromArray:add]; out = [m copy]; }
        else if ([coll isKindOfClass:[NSSet class]]) { out = [coll setByAddingObjectsFromArray:add]; }
        else if ([coll isKindOfClass:[NSArray class]]) {
            NSMutableArray *m = [coll mutableCopy];
            for (NSString *r in add) if (![m containsObject:r]) [m addObject:r];
            out = [m copy];
        }
        if (!out) return coll;
        [cache setObject:out forKey:coll];
        return out;
    }
}

%group G3B_AXRoles
%hook SBFullKeyboardAccessUISceneController
+ (id)_setupInfo {
    id i = %orig;
    return BP_G3B_OptIn("g3b_axroles") ? BP_G3B_SetupInfoWithRole(i, kBPRoleAXFullKeyboard) : i;
}
%end
%hook SBVoiceControlUISceneController
+ (id)_setupInfo {
    id i = %orig;
    return BP_G3B_OptIn("g3b_axroles") ? BP_G3B_SetupInfoWithRole(i, kBPRoleAXVoiceControl) : i;
}
%end
%hook SBAssistiveTouchUISceneController
+ (id)_setupInfo {
    id i = %orig;
    return BP_G3B_OptIn("g3b_axroles") ? BP_G3B_SetupInfoWithRole(i, kBPRoleAXAssistiveTouch) : i;
}
%end
%hook SBAccessibilityUIServerUISceneController
+ (id)_setupInfo {
    id i = %orig;
    return BP_G3B_OptIn("g3b_axroles") ? BP_G3B_SetupInfoWithRole(i, kBPRoleAXUIServer) : i;
}
%end
%hook SBExternalDisplayWindowSceneDelegate
+ (id)_individuallyManagedRoles {
    id r = %orig;
    return BP_G3B_OptIn("g3b_axroles") ? BP_G3B_AppendRoles(r) : r;
}
%end
%hook SBEmbeddedDisplayWindowSceneDelegate
+ (id)_individuallyManagedRoles {
    id r = %orig;
    return BP_G3B_OptIn("g3b_axroles") ? BP_G3B_AppendRoles(r) : r;
}
%end
%hook SBTraitsExternalDisplayRolesAndDefaultPoliciesProvider
- (id)orientationStageRoles {
    id r = %orig;
    return BP_G3B_OptIn("g3b_axroles") ? BP_G3B_AppendRoles(r) : r;
}
%end
%hook SBTraitsEmbeddedDisplayRolesAndDefaultPoliciesProvider
- (id)defaultActiveOrientationBelowDrivenRoles {
    id r = %orig;
    return BP_G3B_OptIn("g3b_axroles") ? BP_G3B_AppendRoles(r) : r;
}
%end
%end // G3B_AXRoles


// ================================================================================================ ITEM 3: PiP per display
// (spec section 3)  DONE. 16.0 keeps one global _SBPIPEndStashTabSuppressionGestureManager (+sharedInstance) that registers its tap recognizers
// with the MAIN display's SBSystemGestureManager; 16.2 owns one per SBWindowScenePIPManager. Reproduced with a new class (the 16.0 class is left alone).
@interface BPPIPEndStashTabSuppressionManager : NSObject <UIGestureRecognizerDelegate>
- (instancetype)initWithSystemGestureManager:(id)manager;
- (void)addTarget:(id)target action:(SEL)action;
- (void)removeTarget:(id)target action:(SEL)action;
- (void)invalidate;
@end

@implementation BPPIPEndStashTabSuppressionManager {
    NSMutableSet *_targets;
    UITapGestureRecognizer *_tap;
    UITapGestureRecognizer *_doubleTap;
    id _sgm;                                          // SBSystemGestureManager of the scene (16.2 +0x20)
}
- (instancetype)initWithSystemGestureManager:(id)manager {      // 16.2 0x1c734020c
    if ((self = [super init])) _sgm = manager;
    return self;
}
- (void)dealloc { [self invalidate]; }                           // 16.2 0x1c7340280: removeAllObjects, _removeGestureRecognizers
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)a shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)b { (void)a; (void)b; return YES; }
- (void)_addSystemRecognizers {                                  // 16.2 0x1c7340510 (16.0 0x1c635d6c0); gesture types are the 16.0 numbers 0x77 / 0x78
    if (_tap || _doubleTap || !_sgm) return;
    UITapGestureRecognizer *tap = [UITapGestureRecognizer new];
    tap.name = @"pip.stashtab.endsuppression.tap";
    tap.cancelsTouchesInView = NO; tap.delaysTouchesBegan = NO; tap.delaysTouchesEnded = NO;
    tap.allowedTouchTypes = @[@(UITouchTypeDirect)];             // constant array 0x1e16fb5d0 = { @0 }
    tap.delegate = self;
    UITapGestureRecognizer *dbl = [UITapGestureRecognizer new];
    dbl.name = @"pip.stashtab.endsuppression.doubletap";
    dbl.numberOfTapsRequired = 2;
    dbl.cancelsTouchesInView = NO; dbl.delaysTouchesBegan = NO; dbl.delaysTouchesEnded = NO;
    dbl.allowedTouchTypes = @[@(UITouchTypeDirect)];
    dbl.delegate = self;
    [tap requireGestureRecognizerToFail:dbl];
    _tap = tap; _doubleTap = dbl;
    SEL add = NSSelectorFromString(@"addGestureRecognizer:withType:");
    if ([_sgm respondsToSelector:add]) {
        ((void (*)(id, SEL, id, long long))objc_msgSend)(_sgm, add, _tap, 0x77);
        ((void (*)(id, SEL, id, long long))objc_msgSend)(_sgm, add, _doubleTap, 0x78);
    }
}
- (void)_removeGestureRecognizers {                              // 16.2 0x1c7340728
    if (_targets.count) return;
    SEL rem = NSSelectorFromString(@"removeGestureRecognizer:");
    if (_tap && [_sgm respondsToSelector:rem]) ((void (*)(id, SEL, id))objc_msgSend)(_sgm, rem, _tap);
    if (_doubleTap && [_sgm respondsToSelector:rem]) ((void (*)(id, SEL, id))objc_msgSend)(_sgm, rem, _doubleTap);
    _tap = nil; _doubleTap = nil;
}
- (void)addTarget:(id)target action:(SEL)action {                // 16.2 0x1c73402e0
    if (!target || !action || [_targets containsObject:target]) return;
    if (!_tap) [self _addSystemRecognizers];
    [_tap addTarget:target action:action];
    if (!_targets) _targets = [NSMutableSet setWithCapacity:1];
    [_targets addObject:target];
}
- (void)removeTarget:(id)target action:(SEL)action {             // 16.2 0x1c7340400
    if (!target || ![_targets containsObject:target]) return;
    [_tap removeTarget:target action:action];
    [_targets removeObject:target];
    if (_targets.count == 0) { _targets = nil; [self _removeGestureRecognizers]; }
}
- (void)invalidate { [_targets removeAllObjects]; _targets = nil; [self _removeGestureRecognizers]; }
@end

static char kBPG3BPipSuppressMgr, kBPG3BPipManagerOfProvider;
static NSString *const kBPG3BWMStyleNote = @"SBSwitcherControllerWindowManagementStyleDidChangeNotification";

@interface NSObject (BPG3BPip)
- (id)systemGestureManager;
- (id)switcherController;
- (id)globalCoordinator;
- (id)windowScene;
- (void)_enumerateControllersByDescendingPriority:(id)block;
- (void)setEnhancedWindowingModeEnabled:(BOOL)e windowScene:(id)scene;
- (void)pipController:(id)c didUpdateEnhancedWindowingModeEnabled:(BOOL)e windowScene:(id)scene;
- (void)addStashTabSuppressionTarget:(id)t action:(SEL)a;
- (void)removeStashTabSuppressionTarget:(id)t action:(SEL)a;
- (void)_windowManagementStyleDidChange:(NSNotification *)n;
- (id)containerViewControllersOnWindowScene:(id)scene;
- (id)hostedAppSceneHandle;
- (void)setWantsEnhancedWindowingEnabled:(BOOL)e;
- (id)sceneIfExists;
- (void)updateSettingsWithBlock:(id)block;
- (void)setEnhancedWindowingEnabled:(BOOL)e;
- (void)stashTabVisibilityPolicyProviderDidUpdatePolicy:(id)p;
- (void)addActiveOrientationObserver:(id)o;
- (void)removeActiveOrientationObserver:(id)o;
- (id)_sbWindowScene;
- (id)sceneManager;
- (id)pictureInPictureManager;
- (BOOL)stashed;
- (BOOL)wantsStashTabSuppression;
- (void)setPrefersStashTabSuppressed:(BOOL)b;
- (id)initWithObserver:(id)o bannerManager:(id)b sceneManager:(id)s;
- (BOOL)isChamoisWindowingUIEnabled;
@end
@interface SBWindowScenePIPManager : NSObject @end
@interface SBPIPController : NSObject @end
@interface SBPIPSceneContentAdapter : NSObject @end
@interface SBPIPPegasusContainerAdapter : NSObject @end
@interface SBPIPStashTabSuppressionPolicyProvider : NSObject @end

%group G3B_PiP

%hook SBWindowScenePIPManager

// 16.2 0x1c733e170: per-scene gesture manager + style-change observer for every display (16.0 registers its three observers for the main display only; unchanged)
- (void)windowSceneDidConnect:(id)scene {
    %orig;
    if (!BP_G3B_On("g3b_pip") || !scene) return;
    if (!objc_getAssociatedObject(self, &kBPG3BPipSuppressMgr)) {
        id sgm = BP_G3B_Send0(scene, NSSelectorFromString(@"systemGestureManager"));
        if (sgm) {
            BPPIPEndStashTabSuppressionManager *m = [[BPPIPEndStashTabSuppressionManager alloc] initWithSystemGestureManager:sgm];
            objc_setAssociatedObject(self, &kBPG3BPipSuppressMgr, m, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
    id sc = BP_G3B_Send0(scene, NSSelectorFromString(@"switcherController"));
    if (sc) [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_windowManagementStyleDidChange:) name:kBPG3BWMStyleNote object:sc];
}
// 16.2 0x1c733e3c8: release the gesture manager
- (void)windowSceneDidDisconnect:(id)scene {
    BPPIPEndStashTabSuppressionManager *m = objc_getAssociatedObject(self, &kBPG3BPipSuppressMgr);
    [m invalidate];
    objc_setAssociatedObject(self, &kBPG3BPipSuppressMgr, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kBPG3BWMStyleNote object:nil];
    %orig;
}
// 16.2 0x1c733f9c4 / 0x1c733f9cc
%new
- (void)addStashTabSuppressionTarget:(id)target action:(SEL)action {
    [(BPPIPEndStashTabSuppressionManager *)objc_getAssociatedObject(self, &kBPG3BPipSuppressMgr) addTarget:target action:action];
}
%new
- (void)removeStashTabSuppressionTarget:(id)target action:(SEL)action {
    [(BPPIPEndStashTabSuppressionManager *)objc_getAssociatedObject(self, &kBPG3BPipSuppressMgr) removeTarget:target action:action];
}
// 16.2 0x1c73400a4
%new
- (void)_windowManagementStyleDidChange:(NSNotification *)n {
    if (!BP_G3B_On("g3b_pip")) return;
    id scene = BP_G3B_Ivar(self, "_windowScene");
    id sc = BP_G3B_Send0(scene, NSSelectorFromString(@"switcherController"));
    BOOL enabled = [sc respondsToSelector:@selector(isChamoisWindowingUIEnabled)] ? ((BOOL (*)(id, SEL))objc_msgSend)(sc, @selector(isChamoisWindowingUIEnabled)) : NO;
    id coord = BP_G3B_Ivar(self, "_globalCoordinator");
    SEL en = NSSelectorFromString(@"_enumerateControllersByDescendingPriority:");
    if (!scene || ![coord respondsToSelector:en]) return;
    void (^blk)(id) = ^(id controller) {
        SEL set = NSSelectorFromString(@"setEnhancedWindowingModeEnabled:windowScene:");
        if ([controller respondsToSelector:set]) ((void (*)(id, SEL, BOOL, id))objc_msgSend)(controller, set, enabled, scene);
    };
    ((void (*)(id, SEL, id))objc_msgSend)(coord, en, blk);
}
%end

%hook SBPIPController
// 16.2 0x1c792c2ec: forward to the adapter (delegate) when it implements the new callback
%new
- (void)setEnhancedWindowingModeEnabled:(BOOL)enabled windowScene:(id)scene {
    id adapter = BP_G3B_Ivar(self, "_adapter");
    SEL cb = NSSelectorFromString(@"pipController:didUpdateEnhancedWindowingModeEnabled:windowScene:");
    if ([adapter respondsToSelector:cb]) ((void (*)(id, SEL, id, BOOL, id))objc_msgSend)(adapter, cb, self, enabled, scene);
}
%end

%hook SBPIPSceneContentAdapter
// 16.2 0x1c77eff9c: every hosted app scene of a PiP container on that window scene follows the Stage Manager state
%new
- (void)pipController:(id)controller didUpdateEnhancedWindowingModeEnabled:(BOOL)enabled windowScene:(id)scene {
    SEL cv = NSSelectorFromString(@"containerViewControllersOnWindowScene:");
    id pip = [controller respondsToSelector:cv] ? controller : BP_G3B_Ivar(self, "_pipController");
    if (!scene || ![pip respondsToSelector:cv]) return;
    for (id c in ((id (*)(id, SEL, id))objc_msgSend)(pip, cv, scene)) {
        id h = BP_G3B_Send0(c, NSSelectorFromString(@"hostedAppSceneHandle"));
        if (!h) continue;
        if ([h respondsToSelector:@selector(setWantsEnhancedWindowingEnabled:)]) ((void (*)(id, SEL, BOOL))objc_msgSend)(h, @selector(setWantsEnhancedWindowingEnabled:), enabled);
        id fbs = BP_G3B_Send0(h, NSSelectorFromString(@"sceneIfExists"));
        if (!fbs) continue;
        SEL upd = NSSelectorFromString(@"updateSettingsWithBlock:");
        if (![fbs respondsToSelector:upd]) continue;
        void (^b)(id) = ^(id settings) {                          // block 0x1c77f015c: BSSafeCast to UIMutableApplicationSceneSettings, setEnhancedWindowingEnabled:
            if ([settings respondsToSelector:@selector(setEnhancedWindowingEnabled:)]) ((void (*)(id, SEL, BOOL))objc_msgSend)(settings, @selector(setEnhancedWindowingEnabled:), enabled);
        };
        ((void (*)(id, SEL, id))objc_msgSend)(fbs, upd, b);
    }
}
%end

%hook SBPIPPegasusContainerAdapter
// 16.2 0x1c78e23d4: the stash-tab policy provider is created for the window scene of the PiP view controller (16.0: always the main display scene manager)
- (void)_createOrInvalidateStashTabVisibilityPolicyProvider {
    long long gestureActive = 0;
    id pipVC = BP_G3B_Ivar(self, "_pictureInPictureViewController");
    BOOL create = BP_G3B_On("g3b_pip") && BP_G3B_ScalarIvar(self, "_isAnyInteractionGestureActive", &gestureActive) && !gestureActive
        && [pipVC respondsToSelector:@selector(stashed)] && ((BOOL (*)(id, SEL))objc_msgSend)(pipVC, @selector(stashed))
        && [pipVC respondsToSelector:@selector(wantsStashTabSuppression)] && ((BOOL (*)(id, SEL))objc_msgSend)(pipVC, @selector(wantsStashTabSuppression));
    if (!create || BP_G3B_Ivar(self, "_stashTabVisibilityPolicyProvider")) {
        %orig;
        return;
    }
    id scene = BP_G3B_Send0(pipVC, NSSelectorFromString(@"_sbWindowScene"));
    id sceneMgr = BP_G3B_Send0(scene, NSSelectorFromString(@"sceneManager"));
    id pipMgr = BP_G3B_Send0(scene, NSSelectorFromString(@"pictureInPictureManager"));
    Class pc = NSClassFromString(@"SBPIPStashTabSuppressionPolicyProvider");
    id bm = BP_G3B_Send0(BP_G3B_App(), NSSelectorFromString(@"bannerManager"));
    if (!sceneMgr || !pipMgr || !pc || !bm) {
        %orig;
        return;
    }
    id p = ((id (*)(id, SEL, id, id, id))objc_msgSend)([pc alloc], NSSelectorFromString(@"initWithObserver:bannerManager:sceneManager:"), self, bm, sceneMgr);
    if (!p) {
        %orig;
        return;
    }
    BP_G3B_SetWeak(p, &kBPG3BPipManagerOfProvider, pipMgr);   // 16.2 +0x48 weak _pipManager
    BP_G3B_SetIvar(self, "_stashTabVisibilityPolicyProvider", p);
}
%end

%hook SBPIPStashTabSuppressionPolicyProvider
// 16.2 0x1c7802b6c: the tap target is registered on the PiP manager of the provider's scene (16.0: the global singleton)
- (void)setStashTabCanBeHidden:(BOOL)canBeHidden {
    id pipMgr = BP_G3B_On("g3b_pip") ? BP_G3B_GetWeak(self, &kBPG3BPipManagerOfProvider) : nil;
    long long cur = 0;
    if (!pipMgr || !BP_G3B_ScalarIvar(self, "_stashTabCanBeHidden", &cur)) {
        %orig;
        return;
    }
    if ((BOOL)cur == canBeHidden) return;
    Ivar iv = class_getInstanceVariable([self class], "_stashTabCanBeHidden");
    *(BOOL *)((char *)(__bridge void *)self + ivar_getOffset(iv)) = canBeHidden;
    id observer = BP_G3B_Ivar(self, "_observer");
    if ([observer respondsToSelector:@selector(stashTabVisibilityPolicyProviderDidUpdatePolicy:)]) [observer stashTabVisibilityPolicyProviderDidUpdatePolicy:self];
    SEL tap = NSSelectorFromString(@"_tapRecognized:");
    id app = BP_G3B_App();
    if (canBeHidden) {
        [pipMgr addStashTabSuppressionTarget:self action:tap];
        if ([app respondsToSelector:@selector(addActiveOrientationObserver:)]) [app addActiveOrientationObserver:self];
    } else {
        [pipMgr removeStashTabSuppressionTarget:self action:tap];
        if ([app respondsToSelector:@selector(removeActiveOrientationObserver:)]) [app removeActiveOrientationObserver:self];
    }
}
%end

%end // G3B_PiP


// ================================================================================================ ITEM 2: per-window-scene hosted keyboard window controller
// (spec section 2)  DONE (decode HIGH; end-user effect UNSURE:see spec). New class BPMedusaHostedKeyboardWindowController = 16.2
// SBMedusaHostedKeyboardWindowController; the 16.0 SBMainDisplaySceneManager entry points forward to the controller of the main display
// window scene, and the other connected display scenes' controllers are updated right after (fan-out).
@interface NSObject (BPG3BKeyboard)
- (id)settings;
- (id)clientSettings;
- (id)preferredSceneHostIdentifier;
- (id)preferredSceneHostIdentity;
- (id)sb_displayIdentityForSceneManagers;
- (id)_fbsDisplayIdentity;
- (BOOL)isForeground;
- (id)externalForegroundApplicationSceneHandles;
- (id)existingSceneHandleForScene:(id)scene;
- (id)layers;
- (BOOL)isKeyboardProxyLayer;
- (id)keyboardOwner;
- (id)clientProcess;
- (BOOL)isApplicationProcess;
- (BOOL)isCurrentProcess;
- (id)bundleIdentifier;
- (id)applicationWithBundleIdentifier:(NSString *)b;
- (id)uiPresentationManager;
- (id)defaultPresentationContext;
- (unsigned long long)presentedLayerTypes;
- (id)uiSettings;
- (BOOL)enhancedWindowingEnabled;
- (BOOL)supportsChamoisSceneResizing;
- (id)pipCoordinator;
- (BOOL)isPresentingPictureInPictureRequiringMedusaKeyboard;
- (void)noteKeyboardIsForMedusaWithOwningScene:(id)scene;
- (void)noteKeyboardIsNotForMedusa;
- (id)keyboardFocusController;
- (id)inputUISceneController;
- (BOOL)isVisibleForSpringBoard;
- (id)windowSceneForDisplayIdentity:(id)identity;
- (id)sceneManagerForDisplayIdentity:(id)identity;
- (id)connectedWindowScenes;
- (id)initWithWindowScene:(id)ws keyboardScene:(id)ks;
- (id)newWindowLevelAssertionWithPriority:(unsigned long long)p windowLevel:(double)l;
- (void)setHidden:(BOOL)h;
- (void)medusaHostedKeyboardWindowWillShow:(NSNotification *)n;
- (void)medusaHostedKeyboardWindowWillHide:(NSNotification *)n;
- (void)_doObserverCalloutWithBlock:(id)b;
- (id)displayIdentity;
- (id)sceneFromIdentityToken:(id)t;
- (id)sceneWithIdentifier:(NSString *)i;
- (void)_updateMedusaHostedKeyboardWindow;
- (id)_bpHostedKeyboardController;
- (id)scene;
+ (id)sharedInstance;
+ (id)mainWorkspace;
@end

static NSString *const kBPG3BKbWillShow = @"_SBMedusaHostedKeyboardWindowWillShowNotification";
static NSString *const kBPG3BKbWillHide = @"_SBMedusaHostedKeyboardWindowWillHideNotification";
static char kBPG3BKbController;

static NSString *BPKB_KeyboardSceneIdentifier(void) {            // __UIKeyboardArbiter_SceneIdentifier (KeyboardArbiter.framework)
    static NSString *ident; static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *const *p = (NSString *const *)dlsym(RTLD_DEFAULT, "_UIKeyboardArbiter_SceneIdentifier");
        ident = (p && *p) ? *p : @"com.apple.UIKit.remote-keyboard";
    });
    return ident;
}
static BOOL BPKB_UsesInputSystemUI(void) {
    Class k = NSClassFromString(@"UIKeyboard");
    SEL s = NSSelectorFromString(@"usesInputSystemUI");
    return [k respondsToSelector:s] ? ((BOOL (*)(id, SEL))objc_msgSend)(k, s) : NO;
}
static id BPKB_FBSceneManager(void) {
    Class c = NSClassFromString(@"FBSceneManager");
    return [c respondsToSelector:@selector(sharedInstance)] ? [c sharedInstance] : nil;
}
static id BPKB_WindowSceneManager(void) { return BP_G3B_Send0(BP_G3B_App(), NSSelectorFromString(@"windowSceneManager")); }

@interface BPMedusaHostedKeyboardWindowController : NSObject
@property (nonatomic, weak) id windowScene;
@property (nonatomic, readonly) id medusaHostedKeyboardWindow;
@property (nonatomic, readonly) BOOL isUsingMedusaHostedKeyboardWindow;
@property (nonatomic, copy) void (^usingDidChange)(void);          // bridge to the 16.0 observers of the main display scene manager
- (instancetype)initWithWindowScene:(id)scene;
- (void)invalidate;
- (void)addObserver:(id)o;
- (void)removeObserver:(id)o;
- (void)updateMedusaHostedKeyboardWindow;
- (void)updateMedusaHostedKeyboardWindowForScene:(id)kbScene isForeground:(BOOL *)outFg;
- (id)newMedusaHostedKeyboardWindowLevelAssertionWithPriority:(unsigned long long)p windowLevel:(double)l;
- (BOOL)isKeyboardVisibleForSpringBoard;
- (BOOL)shouldKeyboardBeWindowSizedForHostWithIdentity:(id)identity;
@end

@implementation BPMedusaHostedKeyboardWindowController {
    NSHashTable *_observers;
    BOOL _using;
    id _window;
}
- (instancetype)initWithWindowScene:(id)scene {                  // 16.2 0x1c7626c38
    if ((self = [super init])) _windowScene = scene;
    return self;
}
- (void)dealloc { [self invalidate]; }
- (void)invalidate {                                              // 16.2 0x1c7626ce8
    id w = _window; _window = nil;
    if ([w respondsToSelector:NSSelectorFromString(@"invalidate")]) ((void (*)(id, SEL))objc_msgSend)(w, NSSelectorFromString(@"invalidate"));
    [_observers removeAllObjects];
}
- (id)medusaHostedKeyboardWindow { return _window; }
- (BOOL)isUsingMedusaHostedKeyboardWindow { return _using; }
- (void)addObserver:(id)o { if (!o) return; if (!_observers) _observers = [NSHashTable weakObjectsHashTable]; [_observers addObject:o]; }
- (void)removeObserver:(id)o { [_observers removeObject:o]; }
- (void)_callout {                                                // _doObserverCalloutWithBlock: 0x1c76280c4 with block 0x1c7627f40 (usingMedusaHostedKeyboardWindowDidChange)
    for (id o in [_observers allObjects]) {
        SEL s = NSSelectorFromString(@"usingMedusaHostedKeyboardWindowDidChange");
        if ([o respondsToSelector:s]) ((void (*)(id, SEL))objc_msgSend)(o, s);
    }
    if (_usingDidChange) _usingDidChange();
}
- (id)newMedusaHostedKeyboardWindowLevelAssertionWithPriority:(unsigned long long)p windowLevel:(double)l {   // 16.2 0x1c762726c
    if (BPKB_UsesInputSystemUI() || !_window) return nil;
    SEL s = NSSelectorFromString(@"newWindowLevelAssertionWithPriority:windowLevel:");
    return [_window respondsToSelector:s] ? ((id (*)(id, SEL, unsigned long long, double))objc_msgSend)(_window, s, p, l) : nil;
}
- (BOOL)isKeyboardVisibleForSpringBoard {                         // 16.2 0x1c76272dc (= 16.0 SBMainDisplaySceneManager _isKeyboardVisibleForSpringBoard 0x1c63d6dfc)
    if (BPKB_UsesInputSystemUI()) {
        Class wc = NSClassFromString(@"SBWorkspace");
        id ws = [wc respondsToSelector:@selector(mainWorkspace)] ? [wc mainWorkspace] : nil;
        id kfc = BP_G3B_Send0(ws, NSSelectorFromString(@"keyboardFocusController"));
        id ui = BP_G3B_Send0(kfc, NSSelectorFromString(@"inputUISceneController"));
        SEL v = NSSelectorFromString(@"isVisibleForSpringBoard");
        return [ui respondsToSelector:v] ? ((BOOL (*)(id, SEL))objc_msgSend)(ui, v) : NO;
    }
    id fbs = BPKB_FBSceneManager();
    id kb = [fbs respondsToSelector:@selector(sceneWithIdentifier:)] ? [fbs sceneWithIdentifier:BPKB_KeyboardSceneIdentifier()] : nil;
    id cs = BP_G3B_Send0(kb, @selector(clientSettings));
    id hostId = BP_G3B_Send0(cs, NSSelectorFromString(@"preferredSceneHostIdentifier"));
    id token = BP_G3B_Send0(cs, NSSelectorFromString(@"preferredSceneHostIdentity"));
    id host = token ? [fbs sceneFromIdentityToken:token] : ([hostId length] ? [fbs sceneWithIdentifier:hostId] : nil);
    id proc = BP_G3B_Send0(host, NSSelectorFromString(@"clientProcess"));
    SEL cur = NSSelectorFromString(@"isCurrentProcess");
    return [proc respondsToSelector:cur] ? ((BOOL (*)(id, SEL))objc_msgSend)(proc, cur) : NO;      // the keyboard is hosted by SpringBoard itself
}
- (BOOL)shouldKeyboardBeWindowSizedForHostWithIdentity:(id)identity {     // 16.2 0x1c7627434
    if (!identity) return NO;
    id host = [BPKB_FBSceneManager() sceneFromIdentityToken:identity];
    if (!host) return NO;
    id proc = BP_G3B_Send0(host, NSSelectorFromString(@"clientProcess"));
    SEL ia = NSSelectorFromString(@"isApplicationProcess");
    if (![proc respondsToSelector:ia] || !((BOOL (*)(id, SEL))objc_msgSend)(proc, ia)) return NO;
    Class ac = NSClassFromString(@"SBApplicationController");
    id app = [[ac sharedInstance] applicationWithBundleIdentifier:BP_G3B_Send0(proc, NSSelectorFromString(@"bundleIdentifier"))];
    id ui = BP_G3B_Send0(host, NSSelectorFromString(@"uiSettings"));
    SEL en = NSSelectorFromString(@"enhancedWindowingEnabled");
    if (![ui respondsToSelector:en] || !((BOOL (*)(id, SEL))objc_msgSend)(ui, en)) return NO;
    SEL sc = NSSelectorFromString(@"supportsChamoisSceneResizing");
    return ![app respondsToSelector:sc] || !((BOOL (*)(id, SEL))objc_msgSend)(app, sc);
}
- (void)updateMedusaHostedKeyboardWindow {                        // 16.2 0x1c7627550
    if (BPKB_UsesInputSystemUI()) return;
    id fbs = BPKB_FBSceneManager();
    id kb = [fbs respondsToSelector:@selector(sceneWithIdentifier:)] ? [fbs sceneWithIdentifier:BPKB_KeyboardSceneIdentifier()] : nil;
    if (kb) [self updateMedusaHostedKeyboardWindowForScene:kb isForeground:NULL];
}
- (void)updateMedusaHostedKeyboardWindowForScene:(id)kbScene isForeground:(BOOL *)outFg {      // 16.2 0x1c76275f4 (16.0 0x1c63d7070)
    if (BPKB_UsesInputSystemUI() || !kbScene) return;
    id ws = _windowScene;
    if (!ws) return;
    id kbSettings = BP_G3B_Send0(kbScene, @selector(settings));
    id dispIdentity = BP_G3B_Send0(kbSettings, NSSelectorFromString(@"sb_displayIdentityForSceneManagers"));
    id myIdentity = BP_G3B_Send0(ws, NSSelectorFromString(@"_fbsDisplayIdentity"));
    if (!dispIdentity || ![dispIdentity isEqual:myIdentity]) return;                    // NEW in 16.2: only the display the keyboard scene is on
    BOOL kbIsFg = ((BOOL (*)(id, SEL))objc_msgSend)(kbSettings, NSSelectorFromString(@"isForeground"));
    BOOL resFg = kbIsFg;                                                                // [sp+0x5c]
    id cs = BP_G3B_Send0(kbScene, @selector(clientSettings));
    NSString *hostId = BP_G3B_Send0(cs, NSSelectorFromString(@"preferredSceneHostIdentifier"));
    id token = BP_G3B_Send0(cs, NSSelectorFromString(@"preferredSceneHostIdentity"));
    Class scc = NSClassFromString(@"SBSceneManagerCoordinator");
    id sceneMgr = [[scc sharedInstance] sceneManagerForDisplayIdentity:myIdentity];    // 16.0 used the main display scene manager (self)
    id fbs = BPKB_FBSceneManager();
    id host = nil;
    if (token) {
        host = [fbs sceneFromIdentityToken:token];
        if (!host) {
            for (id h in [BP_G3B_Send0(sceneMgr, NSSelectorFromString(@"externalForegroundApplicationSceneHandles")) copy]) {
                id sc = BP_G3B_Send0(h, NSSelectorFromString(@"sceneIfExists"));
                id layers = BP_G3B_Send0(BP_G3B_Send0(sc, @selector(clientSettings)), NSSelectorFromString(@"layers"));
                BOOL found = NO;
                for (id layer in layers) {
                    if (((BOOL (*)(id, SEL))objc_msgSend)(layer, NSSelectorFromString(@"isKeyboardProxyLayer")) &&
                        (BP_G3B_Send0(layer, NSSelectorFromString(@"keyboardOwner")) == token || [BP_G3B_Send0(layer, NSSelectorFromString(@"keyboardOwner")) isEqual:token])) { found = YES; break; }
                }
                if (found) { host = sc; break; }
            }
        }
    } else if (hostId.length) {
        host = [fbs sceneWithIdentifier:hostId];
    }
    BOOL forMedusa = NO;
    if (host) {
        id handle = ((id (*)(id, SEL, id))objc_msgSend)(sceneMgr, NSSelectorFromString(@"existingSceneHandleForScene:"), host);
        BOOL hostFg;
        if ([BP_G3B_Send0(sceneMgr, NSSelectorFromString(@"externalForegroundApplicationSceneHandles")) containsObject:handle]) hostFg = YES;
        else if (BP_G3B_Send0(BP_G3B_Send0(handle, NSSelectorFromString(@"sceneIfExists")), NSSelectorFromString(@"workspaceIdentifier")))
            hostFg = ((BOOL (*)(id, SEL))objc_msgSend)(BP_G3B_Send0(BP_G3B_Send0(handle, @selector(scene)), @selector(settings)), NSSelectorFromString(@"isForeground"));
        else hostFg = NO;
        id proc = BP_G3B_Send0(host, NSSelectorFromString(@"clientProcess"));
        id app = nil;
        if ([proc respondsToSelector:NSSelectorFromString(@"isApplicationProcess")] && ((BOOL (*)(id, SEL))objc_msgSend)(proc, NSSelectorFromString(@"isApplicationProcess")))
            app = [[NSClassFromString(@"SBApplicationController") sharedInstance] applicationWithBundleIdentifier:BP_G3B_Send0(proc, NSSelectorFromString(@"bundleIdentifier"))];
        unsigned long long types = 0;
        id ctx = BP_G3B_Send0(BP_G3B_Send0(host, NSSelectorFromString(@"uiPresentationManager")), NSSelectorFromString(@"defaultPresentationContext"));
        if ([ctx respondsToSelector:NSSelectorFromString(@"presentedLayerTypes")]) types = ((unsigned long long (*)(id, SEL))objc_msgSend)(ctx, NSSelectorFromString(@"presentedLayerTypes"));
        NSString *(*sysId)(void) = (NSString *(*)(void))dlsym(RTLD_DEFAULT, "FBSystemAppBundleID");
        if (hostFg && (types & ~2ull) == 0) {                      // foreground app that cannot present the keyboard itself
            forMedusa = YES; resFg = YES;
        } else if (sysId && [hostId isEqualToString:sysId()]) {    // preferred host is SpringBoard
            forMedusa = NO; resFg = YES;
        } else {
            id sc = BP_G3B_Send0(ws, NSSelectorFromString(@"switcherController"));
            BOOL chamois = [sc respondsToSelector:@selector(isChamoisWindowingUIEnabled)] && ((BOOL (*)(id, SEL))objc_msgSend)(sc, @selector(isChamoisWindowingUIEnabled));
            BOOL enhanced = chamois && ((BOOL (*)(id, SEL))objc_msgSend)(BP_G3B_Send0(host, NSSelectorFromString(@"uiSettings")), NSSelectorFromString(@"enhancedWindowingEnabled"));
            BOOL resizable = enhanced && [app respondsToSelector:NSSelectorFromString(@"supportsChamoisSceneResizing")] && ((BOOL (*)(id, SEL))objc_msgSend)(app, NSSelectorFromString(@"supportsChamoisSceneResizing"));
            if (resizable) forMedusa = YES;                         // Chamois window UI: resizable app windows use the Medusa keyboard (resFg unchanged)
            else { forMedusa = NO; resFg = NO; }                    // the host scene can host the keyboard itself
        }
    }
    Class wc = NSClassFromString(@"SBWorkspace");
    id pip = BP_G3B_Send0([wc respondsToSelector:@selector(mainWorkspace)] ? [wc mainWorkspace] : nil, NSSelectorFromString(@"pipCoordinator"));
    SEL preq = NSSelectorFromString(@"isPresentingPictureInPictureRequiringMedusaKeyboard");
    if ([pip respondsToSelector:preq] && ((BOOL (*)(id, SEL))objc_msgSend)(pip, preq)) { forMedusa = YES; resFg = YES; }
    if (!_window) {
        Class winC = NSClassFromString(@"SBMedusaHostedKeyboardWindow");
        id wscene = [BPKB_WindowSceneManager() windowSceneForDisplayIdentity:myIdentity];
        if (!winC || !wscene) return;
        _window = [[winC alloc] initWithWindowScene:wscene keyboardScene:kbScene];
    }
    BP_Log(@"hosted keyboard window %p %s", ws, forMedusa ? "SHOWING" : "HIDING");
    ((void (*)(id, SEL, BOOL))objc_msgSend)(_window, @selector(setHidden:), !forMedusa);
    id coord = [NSClassFromString(@"SBMainSwitcherControllerCoordinator") sharedInstance];
    if (forMedusa) { if ([coord respondsToSelector:@selector(noteKeyboardIsForMedusaWithOwningScene:)]) [coord noteKeyboardIsForMedusaWithOwningScene:host]; }
    else if ([coord respondsToSelector:@selector(noteKeyboardIsNotForMedusa)]) [coord noteKeyboardIsNotForMedusa];
    if (_using != forMedusa) { _using = forMedusa; [self _callout]; }
    if (outFg) *outFg = resFg;
}
@end

static BPMedusaHostedKeyboardWindowController *BPKB_ControllerForWindowScene(id ws) {
    if (!ws) return nil;
    BPMedusaHostedKeyboardWindowController *c = objc_getAssociatedObject(ws, &kBPG3BKbController);
    if (!c) {
        c = [[BPMedusaHostedKeyboardWindowController alloc] initWithWindowScene:ws];
        objc_setAssociatedObject(ws, &kBPG3BKbController, c, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return c;
}
static id BPKB_MainWindowScene(id sceneManager) {                  // window scene of the display of a (main) scene manager
    id ident = BP_G3B_Send0(sceneManager, NSSelectorFromString(@"displayIdentity"));
    return ident ? [BPKB_WindowSceneManager() windowSceneForDisplayIdentity:ident] : nil;
}
static void BPKB_FanOut(id exceptWindowScene, id kbScene) {          // update the controllers of the other connected displays
    id all = BP_G3B_Send0(BPKB_WindowSceneManager(), NSSelectorFromString(@"connectedWindowScenes"));
    for (id ws in [all respondsToSelector:@selector(allObjects)] ? [all allObjects] : all) {
        if (ws == exceptWindowScene) continue;
        BPMedusaHostedKeyboardWindowController *c = BPKB_ControllerForWindowScene(ws);
        if (kbScene) [c updateMedusaHostedKeyboardWindowForScene:kbScene isForeground:NULL];
        else [c updateMedusaHostedKeyboardWindow];
    }
}

%group G3B_KbWindow

%hook SBMainDisplaySceneManager

- (void)_updateMedusaHostedKeyboardWindow {
    if (!BP_G3B_On("g3b_kbwindow")) {
        %orig;
        return;
    }
    id ws = BPKB_MainWindowScene(self);
    BPMedusaHostedKeyboardWindowController *c = BPKB_ControllerForWindowScene(ws);
    if (!c) {
        %orig;
        return;
    }
    __weak id weakSelf = self;
    c.usingDidChange = ^{
        id me = weakSelf;
        if (me) [me _doObserverCalloutWithBlock:^(id obs) {
            SEL s = NSSelectorFromString(@"sceneManagerUsingMedusaHostedKeyboardWindowDidChange:");
            if ([obs respondsToSelector:s]) ((void (*)(id, SEL, id))objc_msgSend)(obs, s, me);
        }];
    };
    [c updateMedusaHostedKeyboardWindow];
    BPKB_FanOut(ws, nil);
}
- (void)_updateMedusaHostedKeyboardWindowForScene:(id)scene isForeground:(BOOL *)fg {
    if (!BP_G3B_On("g3b_kbwindow")) {
        %orig;
        return;
    }
    id ws = BPKB_MainWindowScene(self);
    BPMedusaHostedKeyboardWindowController *c = BPKB_ControllerForWindowScene(ws);
    if (!c) {
        %orig;
        return;
    }
    __weak id weakSelf = self;
    c.usingDidChange = ^{
        id me = weakSelf;
        if (me) [me _doObserverCalloutWithBlock:^(id obs) {
            SEL s = NSSelectorFromString(@"sceneManagerUsingMedusaHostedKeyboardWindowDidChange:");
            if ([obs respondsToSelector:s]) ((void (*)(id, SEL, id))objc_msgSend)(obs, s, me);
        }];
    };
    [c updateMedusaHostedKeyboardWindowForScene:scene isForeground:fg];
    BPKB_FanOut(ws, scene);
}
- (id)_medusaHostedKeyboardWindow {
    if (!BP_G3B_On("g3b_kbwindow")) return %orig;
    id w = [BPKB_ControllerForWindowScene(BPKB_MainWindowScene(self)) medusaHostedKeyboardWindow];
    return w ?: %orig;
}
- (BOOL)_isUsingMedusaHostedKeyboardWindow {
    if (!BP_G3B_On("g3b_kbwindow")) return %orig;
    BPMedusaHostedKeyboardWindowController *c = BPKB_ControllerForWindowScene(BPKB_MainWindowScene(self));
    return c ? c.isUsingMedusaHostedKeyboardWindow : %orig;
}
- (id)newMedusaHostedKeyboardWindowLevelAssertionWithPriority:(unsigned long long)priority windowLevel:(double)level {
    if (!BP_G3B_On("g3b_kbwindow")) return %orig;
    BPMedusaHostedKeyboardWindowController *c = BPKB_ControllerForWindowScene(BPKB_MainWindowScene(self));
    return c ? [c newMedusaHostedKeyboardWindowLevelAssertionWithPriority:priority windowLevel:level] : %orig;
}
%end

// the external display's own scene manager had an empty stub; its transitions now refresh that display's controller
%hook SBSystemShellExternalDisplaySceneManager
- (void)_updateMedusaHostedKeyboardWindow {
    %orig;
    if (!BP_G3B_On("g3b_kbwindow")) return;
    [BPKB_ControllerForWindowScene(BPKB_MainWindowScene(self)) updateMedusaHostedKeyboardWindow];
}
%end

// Window level: 16.2 0x1c75844cc registers for WillShow/WillHide, 0x1c7584c48 posts them, 0x1c7584e00/0x1c7584eb4 deactivate the presenter of the OTHER window
%hook SBMedusaHostedKeyboardWindow
- (id)initWithWindowScene:(id)scene keyboardScene:(id)kb {
    id me = %orig;
    if (me && BP_G3B_On("g3b_kbwindow")) {
        [[NSNotificationCenter defaultCenter] addObserver:me selector:@selector(medusaHostedKeyboardWindowWillShow:) name:kBPG3BKbWillShow object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:me selector:@selector(medusaHostedKeyboardWindowWillHide:) name:kBPG3BKbWillHide object:nil];
    }
    return me;
}
- (void)setHidden:(BOOL)hidden {
    if (BP_G3B_On("g3b_kbwindow")) [[NSNotificationCenter defaultCenter] postNotificationName:(hidden ? kBPG3BKbWillHide : kBPG3BKbWillShow) object:self];
    %orig;
}
%new
- (void)medusaHostedKeyboardWindowWillShow:(NSNotification *)n {
    id presenter = BP_G3B_Ivar(self, "_remoteHostedKeyboardScenePresenter");
    if (n.object == self || !presenter) return;
    SEL act = NSSelectorFromString(@"isActive");
    if ([presenter respondsToSelector:act] && ((BOOL (*)(id, SEL))objc_msgSend)(presenter, act) && [presenter respondsToSelector:NSSelectorFromString(@"deactivate")])
        ((void (*)(id, SEL))objc_msgSend)(presenter, NSSelectorFromString(@"deactivate"));
}
%new
- (void)medusaHostedKeyboardWindowWillHide:(NSNotification *)n {
    [self medusaHostedKeyboardWindowWillShow:n];                    // identical body in 16.2 (0x1c7584eb4)
}
%new
- (void)invalidate {                                                // 16.2 0x1c758486c
    id presenter = BP_G3B_Ivar(self, "_remoteHostedKeyboardScenePresenter");
    id a = BP_G3B_Ivar(self, "_defaultWindowLevelAssertion");
    if ([presenter respondsToSelector:@selector(invalidate)]) [presenter invalidate];
    if ([a respondsToSelector:@selector(invalidate)]) [a invalidate];
}
%end

%end // G3B_KbWindow


// ================================================================================================ ITEM 5: status bar
// (spec section 5)  DONE. 5a: options: API; 5b: per-display frontmost status bar fix; 5c: screenBoundsIgnoresSceneOrientation (nothing to reconstruct, see spec).
@interface UIStatusBar_Base : NSObject @end
@interface _UIStatusBar : NSObject @end
@interface SBWindowSceneStatusBarManager : NSObject @end
@interface SBWindowSceneStatusBarAssertionManager : NSObject @end
@interface SBMainSwitcherControllerCoordinator : NSObject @end
@interface NSObject (BPG3BStatusBar)
- (void)setAvoidanceFrame:(CGRect)frame animationSettings:(id)settings isInteractive:(BOOL)interactive;
- (void)setAvoidanceFrame:(CGRect)frame animationSettings:(id)settings options:(unsigned long long)options;
- (void)setAvoidanceFrame:(CGRect)frame reason:(id)reason statusBar:(id)bar animationSettings:(id)settings isInteractive:(BOOL)interactive;
- (void)setAvoidanceFrame:(CGRect)frame reason:(id)reason statusBar:(id)bar animationSettings:(id)settings options:(unsigned long long)options;
- (BOOL)isFrontmostStatusBarPartHidden:(long long)part;
- (id)layoutState;
- (long long)unlockedEnvironmentMode;
@end

static __thread __unsafe_unretained id gBPG3BSwitcherOverride;

%group G3B_StatusBar

// 16.2 UIKit: -setAvoidanceFrame:animationSettings:options: (bit 0 = interactive, bit 1 = apply immediately even while status bar items animate: only read by
// _UIStatusBarVisualProvider_DynamicSplit, i.e. Dynamic Island iPhones; the Pad provider ignores the argument). 16.0 has only the isInteractive: form.
%hook UIStatusBar_Base
%new
- (void)setAvoidanceFrame:(CGRect)frame animationSettings:(id)settings options:(unsigned long long)options {
    [self setAvoidanceFrame:frame animationSettings:settings isInteractive:(options & 1) != 0];
}
%end
%hook _UIStatusBar
%new
- (void)setAvoidanceFrame:(CGRect)frame animationSettings:(id)settings options:(unsigned long long)options {
    [self setAvoidanceFrame:frame animationSettings:settings isInteractive:(options & 1) != 0];
}
%end
// 16.2 0x1c736bd6c: SBWindowSceneStatusBarManager setAvoidanceFrame:reason:statusBar:animationSettings:options: (16.0 0x1c5ef7994 takes isInteractive:)
%hook SBWindowSceneStatusBarManager
%new
- (void)setAvoidanceFrame:(CGRect)frame reason:(id)reason statusBar:(id)bar animationSettings:(id)settings options:(unsigned long long)options {
    [self setAvoidanceFrame:frame reason:reason statusBar:bar animationSettings:settings isInteractive:(options & 1) != 0];
}
%end

// 16.2 0x1c78a5064: -isFrontmostStatusBarPartHidden: reads layoutState / unlockedEnvironmentMode from the window scene's own switcher controller;
// 16.0 reads them from [SBMainSwitcherControllerCoordinator sharedInstance] (the main display). The two coordinator calls are the only difference
// (selector sequences diffed), so the 16.0 body is run with the coordinator's two getters redirected for the duration of the call.
%hook SBWindowSceneStatusBarAssertionManager
- (BOOL)isFrontmostStatusBarPartHidden:(long long)part {
    if (!BP_G3B_On("g3b_statusbar")) return %orig;
    id scene = BP_G3B_Ivar(self, "_windowScene");
    id sc = BP_G3B_Send0(scene, NSSelectorFromString(@"switcherController"));
    id prev = gBPG3BSwitcherOverride;
    gBPG3BSwitcherOverride = sc;
    BOOL r = %orig;
    gBPG3BSwitcherOverride = prev;
    return r;
}
%end
%hook SBMainSwitcherControllerCoordinator
- (id)layoutState {
    id o = gBPG3BSwitcherOverride;
    if (o && [o respondsToSelector:@selector(layoutState)]) return [o layoutState];
    return %orig;
}
- (long long)unlockedEnvironmentMode {
    id o = gBPG3BSwitcherOverride;
    if (o && [o respondsToSelector:@selector(unlockedEnvironmentMode)]) return [o unlockedEnvironmentMode];
    return %orig;
}
%end

%end // G3B_StatusBar

// ================================================================================================================
// ITEM 1: the user-resize orientation chain (spec section 1)
//   1.1 consumer  : SBMainSwitcherControllerCoordinator -switcherContentController:setInterfaceOrientationFromUserResizing:forDisplayItem:   DONE
//   1.2 producer  : SBItemResizeGestureSwitcherModifier -_responseForSceneSizeUpdateToSize:center:sceneUpdatesOnly:                        DONE
//   1.3 grids     : orthogonal fixed-aspect grid (transposed candidate sizes)                                                           DONE (UNSURE:sort key/candidate set)
//   1.4 traits    : BPG3BTraitsGuide = SBSwitcherTraitsAssistant guiding participants (portrait-only / landscape-only)                  DONE (UNSURE:live-overlay policy interplay)
//   1.5 handle    : orientation selection without the 16.0 phone-on-pad special case                                                    DONE
//   1.6 split     : content vs container orientation API on the scene view controllers (adapter)                                        DONE as adapter, UNSURE:rendering
//   1.7 overlays  : SBDeviceApplicationSceneOverlayBasicWrapperView(+ViewController), SBFluidSwitcherPortaledSceneLiveContentOverlay    DONE as classes; no creator (cross-display drag) -> UNSURE
// Prerequisites (other packages): group1b (response class type 38 + _performEventResponse: branch), group2 (-layoutRestrictionInfoForItem: and
// -supportedContentInterfaceOrientationsForItem: %new on SBSwitcherModifier), group3 G3_Handle (the handle's -_interfaceOrientationFromUserResizing accessors).
// ================================================================================================================
#define BPS(n) NSSelectorFromString(@n)

@interface SBItemResizeGestureSwitcherModifier : NSObject @end
@interface SBDisplayItemLayoutGrid : NSObject @end
@interface _SBDisplayItemFixedAspectGrid : NSObject @end
@interface SBDeviceApplicationSceneHandle : NSObject @end
@interface SBSceneHandle : NSObject @end
@interface SBApplication : NSObject @end

// thread-local state (all hooks run on the main thread, TLS only scopes the dynamic extent of one call)
static __thread int tBPOrthDepth;     // > 0 inside a user-resize modifier method whose item may use orthogonal sizes
static __thread int tBPOrthBuild;     // > 0 while an orthogonal fixed grid is being created
static __thread int tBPOrthMerge;     // > 0 while the transposed build is running (re-entrancy guard)
static __thread int tBPNoPhoneOnPad;  // > 0 while classicAppPhoneAppRunningOnPad must answer NO (16.2 launch semantics)

static BOOL BPG3BO_Bool0(id o, SEL s) { return (o && [o respondsToSelector:s]) ? ((BOOL (*)(id, SEL))objc_msgSend)(o, s) : NO; }
static unsigned long long BPG3BO_ULL0(id o, SEL s) { return (o && [o respondsToSelector:s]) ? ((unsigned long long (*)(id, SEL))objc_msgSend)(o, s) : 0; }
static id BPG3BO_Obj1(id o, SEL s, id a) { return (o && [o respondsToSelector:s]) ? ((id (*)(id, SEL, id))objc_msgSend)(o, s, a) : nil; }
static unsigned long long BPG3BO_ULL1(id o, SEL s, id a) { return (o && [o respondsToSelector:s]) ? ((unsigned long long (*)(id, SEL, id))objc_msgSend)(o, s, a) : 0; }

// ---------------------------------------------------------------------------------------------- 1.4 traits guide
// 16.2 SBSwitcherTraitsAssistant (guiding part only). Two extra participants with role SwitcherLiveOverlay whose only preference is a
// supported-orientation mask (portrait 0x6 / landscape 0x18). Element participants of "guided" windows are given an orientation resolution policy
// "follow the guiding participant" (SBFTraitsOrientationResolutionPolicyInfo resolutionPolicyInfoForAssociatedParticipantWithUniqueID:), so the
// arbiter resolves the app's orientation from the window shape instead of the device.
// Guide selection (16.2 -_setupGuidingRelationshipIfNeededForParticipant:withSceneHandle: 0x1c74d71ac, decoded):
//   medusa-capable app                       -> no guide
//   phone app on pad                         -> portrait guide; landscape guide if (handle supports old-style mixed orientation && prefers landscape)
//   other classic app on an external display -> portrait guide if contentContainerAspectRatio <= 1 else landscape guide
//   else                                     -> none
//   then, for non-medusa apps: Stage Manager on: userResizing 3/4 -> landscape guide, 1/2 -> portrait guide (wins over the above)
//                              Stage Manager off: handle.userResizing = participant.currentOrientation
//   (scene-orientation-request guide: left on the 16.0 AlterEgo path, UNSURE)
static char kBPG3BGuideKey;

@interface BPG3BTraitsGuide : NSObject
@property (nonatomic, weak) id switcher;
@property (nonatomic, strong) id portrait;
@property (nonatomic, strong) id landscape;
@property (nonatomic, strong) id policySpecifier;
@property (nonatomic, strong) NSMutableDictionary *assoc;      // element participant uniqueIdentifier -> guide participant uniqueIdentifier
@property (nonatomic, strong) NSMutableSet *touched;           // element participants we set a policy on
@property (nonatomic, strong) NSMutableArray *tokens;
- (void)install;
- (void)refresh:(NSString *)reason;
@end

@implementation BPG3BTraitsGuide
- (instancetype)init {
    if ((self = [super init])) { _assoc = [NSMutableDictionary new]; _touched = [NSMutableSet new]; _tokens = [NSMutableArray new]; }
    return self;
}
- (void)dealloc {
    for (id t in _tokens) [[NSNotificationCenter defaultCenter] removeObserver:t];
    for (id p in @[ _portrait ?: [NSNull null], _landscape ?: [NSNull null], _policySpecifier ?: [NSNull null] ])
        if ([p respondsToSelector:@selector(invalidate)]) ((void (*)(id, SEL))objc_msgSend)(p, @selector(invalidate));
}
- (id)acquireWithMask:(BOOL)isLandscape {
    id sc = self.switcher;
    id arbiter = BP_G3B_Send0(sc, BPS("traitsArbiter"));
    SEL s = BPS("acquireParticipantWithRole:delegate:");
    if (!arbiter || ![arbiter respondsToSelector:s]) return nil;
    NSString *role = @"SBTraitsParticipantRoleSwitcherLiveOverlay";
    void *sym = dlsym(RTLD_DEFAULT, "SBTraitsParticipantRoleSwitcherLiveOverlay");
    if (sym) { NSString *v = *(__unsafe_unretained NSString **)sym; if ([v isKindOfClass:[NSString class]]) role = v; }
    id p = ((id (*)(id, SEL, id, id))objc_msgSend)(arbiter, s, role, self);
    if (p && [p respondsToSelector:BPS("setNeedsUpdatePreferencesWithReason:")])
        ((void (*)(id, SEL, id))objc_msgSend)(p, BPS("setNeedsUpdatePreferencesWithReason:"), isLandscape ? @"BPG3B landscape guide" : @"BPG3B portrait guide");
    return p;
}
- (id)portraitGuide  { if (!_portrait)  _portrait  = [self acquireWithMask:NO];  return _portrait; }
- (id)landscapeGuide { if (!_landscape) _landscape = [self acquireWithMask:YES]; return _landscape; }

// SBFTraitsParticipantDelegate (16.2 0x1c74d6f68 / 0x1c74d71a8)
- (void)updatePreferencesForParticipant:(id)participant updater:(id)updater {
    unsigned long long mask = (participant == _landscape) ? 0x18 : (participant == _portrait ? 0x6 : 0);
    if (!mask || ![updater respondsToSelector:BPS("updateOrientationPreferencesWithBlock:")]) return;
    void (^blk)(id) = ^(id prefs) {
        if ([prefs respondsToSelector:BPS("setSupportedOrientations:")])
            ((void (*)(id, SEL, unsigned long long))objc_msgSend)(prefs, BPS("setSupportedOrientations:"), mask);
    };
    ((void (*)(id, SEL, id))objc_msgSend)(updater, BPS("updateOrientationPreferencesWithBlock:"), blk);
}
- (void)didChangeSettingsForParticipant:(id)participant context:(id)context {}

- (BOOL)aspectIsPortrait {      // 16.2 _isContentContainerAspectRatioPortrait: contentContainerAspectRatio <= 1 (UNSURE: the compared constant is 1.0; ratio taken as width/height of the window scene)
    id ws = BP_G3B_Send0(self.switcher, BPS("windowScene"));
    CGRect b = CGRectZero;
    id cs = BP_G3B_Send0(ws, BPS("coordinateSpace"));
    if ([cs respondsToSelector:@selector(bounds)]) b = ((CGRect (*)(id, SEL))objc_msgSend)(cs, @selector(bounds));
    return b.size.height <= 0 || (b.size.width / b.size.height) <= 1.0;
}

- (id)guideForParticipant:(id)p handle:(id)h {
    id app = BP_G3B_Send0(h, BPS("application"));
    if (!app || BPG3BO_Bool0(app, BPS("isMedusaCapable"))) return nil;
    id sc = self.switcher;
    BOOL chamois = BPG3BO_Bool0(sc, BPS("isChamoisWindowingUIEnabled"));
    id g = nil;
    if (BPG3BO_Bool0(app, BPS("classicAppPhoneAppRunningOnPad"))) {
        g = [self portraitGuide];
        if (BPG3BO_Bool0(h, BPS("_classicAppPhoneOnPadSupportsOldStyleMixedOrientation")) && BPG3BO_Bool0(h, BPS("_classicAppPhoneOnPadPrefersLandscape")))
            g = [self landscapeGuide];
    } else if (BPG3BO_Bool0(BP_G3B_Send0(sc, BPS("windowScene")), BPS("isExternalDisplayWindowScene"))) {
        g = [self aspectIsPortrait] ? [self portraitGuide] : [self landscapeGuide];
    }
    if (chamois) {
        long long u = BP_G3B_SendLL(h, BPS("_interfaceOrientationFromUserResizing"));
        if (u) g = (u == 3 || u == 4) ? [self landscapeGuide] : [self portraitGuide];
    } else {
        long long cur = BP_G3B_SendLL(p, BPS("currentOrientation"));
        if (cur && [h respondsToSelector:BPS("_setInterfaceOrientationFromUserResizing:")])
            ((void (*)(id, SEL, long long))objc_msgSend)(h, BPS("_setInterfaceOrientationFromUserResizing:"), cur);
    }
    return g;
}

- (void)recompute {
    id sc = self.switcher;
    NSDictionary *parts = BP_G3B_Ivar(sc, "_traitsParticipantsByElementIdentifier");
    NSDictionary *dels = BP_G3B_Ivar(sc, "_traitsDelegateByParticipant");
    if (![parts isKindOfClass:[NSDictionary class]] || ![dels isKindOfClass:[NSDictionary class]]) return;
    [self.assoc removeAllObjects];
    for (id p in [parts allValues]) {
        id del = [dels objectForKey:p];
        id h = BP_G3B_Send0(del, BPS("sceneHandle"));
        if (!h) continue;
        id g = [self guideForParticipant:p handle:h];
        id uid = BP_G3B_Send0(p, BPS("uniqueIdentifier")), gid = BP_G3B_Send0(g, BPS("uniqueIdentifier"));
        if (uid && gid) self.assoc[uid] = gid;
    }
}

// 16.2 -_updateAcquiredParticipantsPolicies: 0x1c74d80d0 (called from the block policy specifier, once per arbitration)
- (void)applyToParticipants:(id)participants {
    Class infoCls = NSClassFromString(@"SBFTraitsOrientationResolutionPolicyInfo");
    SEL mk = BPS("resolutionPolicyInfoForAssociatedParticipantWithUniqueID:");
    if (!infoCls || ![infoCls respondsToSelector:mk] || ![participants conformsToProtocol:@protocol(NSFastEnumeration)]) return;
    [self recompute];
    for (id p in participants) {
        if (![p respondsToSelector:BPS("setOrientationResolutionPolicyInfo:")]) continue;
        id uid = BP_G3B_Send0(p, BPS("uniqueIdentifier"));
        id gid = uid ? self.assoc[uid] : nil;
        if (gid) {
            id info = ((id (*)(id, SEL, id))objc_msgSend)(infoCls, mk, gid);
            ((void (*)(id, SEL, id))objc_msgSend)(p, BPS("setOrientationResolutionPolicyInfo:"), info);
            [self.touched addObject:uid];
        } else if (uid && [self.touched containsObject:uid]) {          // we set it before: take it back (16.2 never clears; 16.0 needs it because guides can disappear)
            ((void (*)(id, SEL, id))objc_msgSend)(p, BPS("setOrientationResolutionPolicyInfo:"), nil);
            [self.touched removeObject:uid];
        }
    }
}

- (void)install {
    id sc = self.switcher;
    if (!sc || self.policySpecifier) return;
    id arbiter = BP_G3B_Send0(sc, BPS("traitsArbiter"));
    Class psc = NSClassFromString(@"SBTraitsPipelineBlockBasedPolicySpecifier");
    SEL isel = BPS("initWithPolicySpecifierBlock:specifierDescription:componentOrder:arbiter:");
    if (!arbiter || !psc || ![psc instancesRespondToSelector:isel]) return;
    __weak BPG3BTraitsGuide *w = self;
    id blk = ^(id participants) { [w applyToParticipants:participants]; };           // block argument: the acquired participants (UNSURE:exact type, guarded)
    id spec = ((id (*)(id, SEL, id, id, id, id))objc_msgSend)([psc alloc], isel, blk, @"Switcher Traits Assistant", @6, arbiter);
    self.policySpecifier = spec;
    for (NSString *n in @[ @"SBClassicPhoneSceneOrientationPreferenceChanged", @"SBSceneGeometryOrientationRequestChanged" ]) {
        id t = [[NSNotificationCenter defaultCenter] addObserverForName:n object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
            [w refresh:note.name];
        }];
        [self.tokens addObject:t];
    }
}

// 16.2 -_handleUpdateRequest: -> setNeedsUpdateArbitrationWithContext:(reason, forceOrientationResolution)
- (void)refresh:(NSString *)reason {
    id sc = self.switcher;
    id arbiter = BP_G3B_Send0(sc, BPS("traitsArbiter"));
    Class cc = NSClassFromString(@"SBFTraitsArbiterUpdateContext");
    SEL ns = BPS("setNeedsUpdateArbitrationWithContext:"), ib = BPS("initWithBuilder:");
    [self recompute];
    if (arbiter && cc && [arbiter respondsToSelector:ns] && [cc instancesRespondToSelector:ib]) {
        void (^builder)(id) = ^(id b) {
            if ([b respondsToSelector:BPS("setReason:")]) ((void (*)(id, SEL, id))objc_msgSend)(b, BPS("setReason:"), reason ?: @"BPG3B");
            if ([b respondsToSelector:BPS("setForceOrientationResolution:")]) ((void (*)(id, SEL, BOOL))objc_msgSend)(b, BPS("setForceOrientationResolution:"), YES);
        };
        id ctx = ((id (*)(id, SEL, id))objc_msgSend)([cc alloc], ib, builder);
        if (ctx) { ((void (*)(id, SEL, id))objc_msgSend)(arbiter, ns, ctx); return; }
    }
    id part = BP_G3B_Ivar(sc, "_traitsParticipant");        // fallback: poke the switcher's own participant (UNSURE)
    if ([part respondsToSelector:BPS("setNeedsUpdatePreferencesWithReason:")])
        ((void (*)(id, SEL, id))objc_msgSend)(part, BPS("setNeedsUpdatePreferencesWithReason:"), reason ?: @"BPG3B");
}
@end

// ---------------------------------------------------------------------------------------------- 1.7 overlay classes (new in 16.2)
// SBDeviceApplicationSceneOverlayBasicWrapperView (16.2 0x1c7951818..0x1c7951858, all trivial) and ...ViewController (0x1c7951424..0x1c79517c4).
@interface SBDeviceApplicationSceneOverlayBasicWrapperView : UIView
@property (nonatomic) long long hostOrientation;
@property (nonatomic) BOOL shouldLayoutOverlayImmediatelyForContainerGeometryChange;
@property (nonatomic, readonly) BOOL needsCounterRotation;
- (void)addObserver:(id)observer;
- (void)removeObserver:(id)observer;
@end
@implementation SBDeviceApplicationSceneOverlayBasicWrapperView
- (BOOL)needsCounterRotation { return NO; }
- (void)addObserver:(id)observer {}
- (void)removeObserver:(id)observer {}
@end

@interface SBDeviceApplicationSceneOverlayBasicWrapperViewController : UIViewController
- (instancetype)initWithContentViewController:(UIViewController *)controller;
- (UIView *)overlayView;
@end
@implementation SBDeviceApplicationSceneOverlayBasicWrapperViewController {
    UIViewController *_contentViewController;
    SBDeviceApplicationSceneOverlayBasicWrapperView *_contentWrapperView;
}
- (instancetype)initWithContentViewController:(UIViewController *)controller {
    if ((self = [super initWithNibName:nil bundle:nil])) _contentViewController = controller;
    return self;
}
- (void)loadView {
    _contentWrapperView = [[SBDeviceApplicationSceneOverlayBasicWrapperView alloc] initWithFrame:CGRectZero];
    self.view = _contentWrapperView;
}
- (UIView *)overlayView { [self loadViewIfNeeded]; return _contentWrapperView; }
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    UIView *cv = _contentViewController.view;
    [_contentViewController beginAppearanceTransition:YES animated:animated];
    [self addChildViewController:_contentViewController];
    [_contentWrapperView addSubview:cv];
    [_contentViewController didMoveToParentViewController:self];
}
- (void)viewDidAppear:(BOOL)animated { [super viewDidAppear:animated]; [_contentViewController endAppearanceTransition]; }
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [_contentViewController beginAppearanceTransition:NO animated:animated];
    [_contentViewController willMoveToParentViewController:nil];
}
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [_contentViewController.view removeFromSuperview];
    [_contentViewController removeFromParentViewController];
    [_contentViewController endAppearanceTransition];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    _contentViewController.view.frame = _contentWrapperView.bounds;
}
@end

// SBFluidSwitcherPortaledSceneLiveContentOverlay (16.2 0x1c78a6520..0x1c78a6880). Used by the cross-display window drag: a portal onto another
// display's live scene view. The creator (SBFullScreenSwitcherLiveContentOverlayCoordinator -_updatePortaledSceneLiveContentOverlays 0x1c74ce070)
// needs enumerateSwitcherControllersWithBlock: / convertAppLayout:fromSwitcherController: which are cross-display-drag plumbing: NOT in this package (UNSURE).
@interface SBFluidSwitcherPortaledSceneLiveContentOverlay : NSObject
@property (nonatomic) BOOL wantsEnhancedWindowingEnabled;
@property (nonatomic) BOOL resizesHostedContext;
@property (nonatomic, weak) id delegate;
@property (nonatomic, readonly) id sceneHandle;
@property (nonatomic, readonly) long long contentOrientation;
@property (nonatomic, readonly) long long containerOrientation;
@property (nonatomic, readonly) UIView *livePortalView;
@property (nonatomic, readonly) UIView *sizeObservingView;
@property (nonatomic, readonly) UIView *sceneView;
@property (nonatomic, readonly) CGSize referenceSize;
- (instancetype)initWithSceneHandle:(id)handle referenceSize:(CGSize)size contentOrientation:(long long)c containerOrientation:(long long)k livePortalView:(UIView *)portal isInsetForHomeAffordance:(BOOL)inset;
@end
@implementation SBFluidSwitcherPortaledSceneLiveContentOverlay
- (instancetype)initWithSceneHandle:(id)handle referenceSize:(CGSize)size contentOrientation:(long long)c containerOrientation:(long long)k livePortalView:(UIView *)portal isInsetForHomeAffordance:(BOOL)inset {
    if ((self = [super init])) {
        _sceneHandle = handle; _referenceSize = size; _contentOrientation = c; _containerOrientation = k; _livePortalView = portal;
        SEL n16_2 = BPS("newSceneViewWithReferenceSize:contentOrientation:containerOrientation:hostRequester:");
        SEL n16_0 = BPS("newSceneViewWithReferenceSize:orientation:hostRequester:");
        void *raw = NULL;
        if ([handle respondsToSelector:n16_2]) raw = ((void *(*)(id, SEL, CGSize, long long, long long, id))objc_msgSend)(handle, n16_2, size, c, k, self);
        else if ([handle respondsToSelector:n16_0]) raw = ((void *(*)(id, SEL, CGSize, long long, id))objc_msgSend)(handle, n16_0, size, c, self);
        _sceneView = raw ? (__bridge_transfer UIView *)raw : nil;                       // newXxx returns +1
        if ([_sceneView respondsToSelector:BPS("setInsetForHomeAffordance:")]) ((void (*)(id, SEL, BOOL))objc_msgSend)(_sceneView, BPS("setInsetForHomeAffordance:"), inset);
        if ([_sceneView respondsToSelector:BPS("setCustomContentView:")]) ((void (*)(id, SEL, id))objc_msgSend)(_sceneView, BPS("setCustomContentView:"), portal);
        if ([_sceneView respondsToSelector:BPS("setDisplayMode:animationFactory:completion:")])
            ((void (*)(id, SEL, long long, id, id))objc_msgSend)(_sceneView, BPS("setDisplayMode:animationFactory:completion:"), 1, nil, nil);
        Class sov = NSClassFromString(@"SBUISizeObservingView");
        UIView *v = sov ? [[sov alloc] initWithFrame:(CGRect){ CGPointZero, size }] : [[UIView alloc] initWithFrame:(CGRect){ CGPointZero, size }];
        _sizeObservingView = v;
        if ([v respondsToSelector:BPS("setDelegate:")]) ((void (*)(id, SEL, id))objc_msgSend)(v, BPS("setDelegate:"), self);
        if (portal) [v addSubview:portal];
        [self sizeObservingView:v didChangeSize:v.bounds.size];
    }
    return self;
}
- (void)sizeObservingView:(id)view didChangeSize:(CGSize)size { if (view == _sizeObservingView) _livePortalView.frame = _sizeObservingView.bounds; }
- (NSString *)sceneViewPresentationIdentifier:(id)i { return NSStringFromClass([self class]); }
- (long long)sceneViewPresentationPriority:(id)p { return -1; }
- (id)contentOverlayView { return _sizeObservingView; }
- (void)setStatusBarHidden:(BOOL)h nubViewHidden:(BOOL)n animator:(id)a {}
- (void)setDimmed:(BOOL)d {}
- (void)setMatchMovedToScene:(BOOL)m {}
- (BOOL)isContentUpdating { return NO; }
- (BOOL)isInsetForHomeAffordance { return BPG3BO_Bool0(_sceneView, BPS("isInsetForHomeAffordance")); }
- (void)setInsetForHomeAffordance:(BOOL)i { if ([_sceneView respondsToSelector:BPS("setInsetForHomeAffordance:")]) ((void (*)(id, SEL, BOOL))objc_msgSend)(_sceneView, BPS("setInsetForHomeAffordance:"), i); }
- (void)setUsesBrightSceneViewBackgroundMaterial:(BOOL)b {}
- (void)noteKeyboardFocusDidChangeToSceneID:(id)i {}
- (void)setBlurViewIconScale:(double)s {}
- (BOOL)isAsyncRenderingEnabled { return NO; }
- (void)setAsyncRenderingEnabled:(BOOL)e withMinificationFilterEnabled:(BOOL)m {}
- (void)disableAsynchronousRenderingForNextCommit {}
- (BOOL)requiresLegacyRotationSupport { return NO; }
- (long long)touchBehavior { return 0; }
- (void)setTouchBehavior:(long long)b {}
- (long long)preferredInterfaceOrientation { return 0; }
- (unsigned long long)supportedInterfaceOrientations { return 0x1e; }
- (id)prepareOverlayForContentRotation { return nil; }
- (long long)leadingStatusBarStyle { return 0; }
- (long long)trailingStatusBarStyle { return 0; }
- (unsigned long long)styleOverridesToSuppress { return 0; }
- (double)currentStatusBarHeight { return 0; }                                  // UNSURE: 16.2 loads a global constant here
- (id)liveSceneIdentityToken { return nil; }
- (id)overlaySceneHandle { return nil; }
- (void)setDisplayLayoutElementActive:(BOOL)a {}
- (BOOL)isDisplayLayoutElementActive { return NO; }
- (long long)overlayType { return 4; }
- (id)contentViewController { return nil; }
- (void)configureWithWorkspaceEntity:(id)e referenceFrame:(CGRect)f contentOrientation:(long long)c containerOrientation:(long long)k layoutRole:(long long)r spaceConfiguration:(long long)s floatingConfiguration:(long long)fc hasClassicAppOrientationMismatch:(BOOL)m {}
- (void)invalidate {}
@end

// ---------------------------------------------------------------------------------------------- 1.6 content / container orientation adapter
// 16.2 SBSceneViewController -setContentReferenceSize:withContentOrientation:andContainerOrientation: (0x1c7964bc0) still forwards only the CONTENT orientation to
// the scene view (-_updateReferenceSize:andOrientation:); the container orientation is just a new stored ivar read by SBAppContainerViewController /
// transient overlays. 16.0 already has the content/container transform split in SBOrientationTransformWrapperView, so the adapter stores the container
// orientation per object (associated object) and forwards the content orientation to the 16.0 selector. Container orientation defaults to the content one.
static char kBPG3BContainerOri;
static long long BPG3BO_ContentOri(id self, SEL _cmd) { return BP_G3B_SendLL(self, BPS("contentInterfaceOrientation")); }
static long long BPG3BO_ContainerOri(id self, SEL _cmd) {
    NSNumber *n = objc_getAssociatedObject(self, &kBPG3BContainerOri);
    return n ? n.longLongValue : BP_G3B_SendLL(self, BPS("contentInterfaceOrientation"));
}
static void BPG3BO_SetRefSize(id self, SEL _cmd, CGSize size, long long content, long long container) {
    objc_setAssociatedObject(self, &kBPG3BContainerOri, @(container), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    SEL old = BPS("setContentReferenceSize:withInterfaceOrientation:");
    if ([self respondsToSelector:old]) ((void (*)(id, SEL, CGSize, long long))objc_msgSend)(self, old, size, content);
}
// handle: newSceneViewWithReferenceSize:contentOrientation:containerOrientation:hostRequester:  (+1 return, so NS_RETURNS_RETAINED)
static __attribute__((ns_returns_retained)) id BPG3BO_NewSceneView(id self, SEL _cmd, CGSize size, long long content, long long container, id requester) {
    SEL old = BPS("newSceneViewWithReferenceSize:orientation:hostRequester:");
    if (![self respondsToSelector:old]) return nil;
    void *raw = ((void *(*)(id, SEL, CGSize, long long, id))objc_msgSend)(self, old, size, content, requester);
    if (raw) { id v = (__bridge id)raw; objc_setAssociatedObject(v, &kBPG3BContainerOri, @(container), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    return raw ? (__bridge_transfer id)raw : nil;
}
static void BPG3BO_AddAdapter(const char *cls) {
    Class c = objc_getClass(cls);
    if (!c) return;
    if (![c instancesRespondToSelector:BPS("contentOrientation")]) class_addMethod(c, BPS("contentOrientation"), (IMP)BPG3BO_ContentOri, "q16@0:8");
    if (![c instancesRespondToSelector:BPS("containerOrientation")]) class_addMethod(c, BPS("containerOrientation"), (IMP)BPG3BO_ContainerOri, "q16@0:8");
    if (![c instancesRespondToSelector:BPS("setContentReferenceSize:withContentOrientation:andContainerOrientation:")])
        class_addMethod(c, BPS("setContentReferenceSize:withContentOrientation:andContainerOrientation:"), (IMP)BPG3BO_SetRefSize, "v48@0:8{CGSize=dd}16q32q40");
}

// ---------------------------------------------------------------------------------------------- groups
static char kBPG3BOrthCache;

static id BPG3BO_ModifierItem(id mod) {
    id layout = BP_G3B_Ivar(mod, "_currentAppLayout");
    long long role = 0;
    if (!layout || !BP_G3B_ScalarIvar(mod, "_selectedLayoutRole", &role)) return nil;
    SEL s = BPS("itemForLayoutRole:");
    return [layout respondsToSelector:s] ? ((id (*)(id, SEL, long long))objc_msgSend)(layout, s, role) : nil;
}
// 16.2 SBItemResizeGestureSwitcherModifier -layoutRestrictionInfoForItem: (0x1c76bf73c): restrictions & 0xA (fixed) && content orientations contain
// both portrait (0x6) and landscape (0x18) -> clear the "no orthogonal sizes" bit 0x8. In 16.0's mask encoding (2 = fixed) this reads: fixed && both.
static BOOL BPG3BO_ItemAllowsOrthogonal(id mod, id item) {
    if (!mod || !item || !BP_G3B_On("g3b_orient")) return NO;
    id calc = BP_G3B_Send0(mod, BPS("displayItemLayoutAttributesCalculator"));
    id info = BPG3BO_Obj1(calc, BPS("layoutRestrictionInfoForItem:"), item);
    if (!info || BPG3BO_ULL0(info, BPS("layoutRestrictions")) != 2) return NO;
    unsigned long long sup = BPG3BO_ULL1(mod, BPS("supportedContentInterfaceOrientationsForItem:"), item);     // group2 %new
    return (sup & 0x6) && (sup & 0x18);
}

// find the NSArray ivar of a grid by NAME suffix (16.0 _SBDisplayItemFlexibleGrid has _widths/_heights; checked by name, not by offset)
static Ivar BPG3BO_ArrayIvar(id obj, const char *name) {
    for (Class c = [obj class]; c; c = class_getSuperclass(c)) {
        Ivar iv = class_getInstanceVariable(c, name);
        if (iv) { const char *e = ivar_getTypeEncoding(iv); return (e && e[0] == '@') ? iv : NULL; }
    }
    return NULL;
}
static void BPG3BO_MergeTransposed(id grid, double scale) {
    Ivar fs = class_getInstanceVariable([grid class], "_fixedSize");
    Ivar wi = BPG3BO_ArrayIvar(grid, "_widths"), hi = BPG3BO_ArrayIvar(grid, "_heights");
    SEL build = BPS("_buildFixedGridWithScreenScale:");
    if (!fs || !wi || !hi || ![grid respondsToSelector:build]) return;
    NSArray *w0 = [object_getIvar(grid, wi) copy], *h0 = [object_getIvar(grid, hi) copy];
    if (![w0 isKindOfClass:[NSArray class]] || w0.count == 0 || w0.count != h0.count) return;
    CGSize *p = (CGSize *)((char *)(__bridge void *)grid + ivar_getOffset(fs));
    CGSize orig = *p;
    *p = CGSizeMake(orig.height, orig.width);
    tBPOrthMerge++;
    ((void (*)(id, SEL, double))objc_msgSend)(grid, build, scale);
    tBPOrthMerge--;
    *p = orig;
    NSArray *w1 = [object_getIvar(grid, wi) copy], *h1 = [object_getIvar(grid, hi) copy];
    if (![w1 isKindOfClass:[NSArray class]] || w1.count != h1.count) { object_setIvar(grid, wi, w0); object_setIvar(grid, hi, h0); return; }
    NSMutableArray *pairs = [NSMutableArray new];
    void (^add)(NSArray *, NSArray *) = ^(NSArray *ws, NSArray *hs) {
        for (NSUInteger i = 0; i < ws.count; i++) {
            double w = [ws[i] doubleValue], h = [hs[i] doubleValue];
            BOOL dup = NO;
            for (NSArray *q in pairs) if (fabs([q[0] doubleValue] - w) < 0.5 && fabs([q[1] doubleValue] - h) < 0.5) { dup = YES; break; }
            if (!dup) [pairs addObject:@[ @(w), @(h) ]];
        }
    };
    add(w0, h0); add(w1, h1);
    [pairs sortUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) {      // UNSURE: 16.2 sorts with sortUsingComparator:; key assumed (width, then height)
        NSComparisonResult r = [a[0] compare:b[0]];
        return r != NSOrderedSame ? r : [a[1] compare:b[1]];
    }];
    NSMutableArray *mw = [NSMutableArray new], *mh = [NSMutableArray new];
    for (NSArray *q in pairs) { [mw addObject:q[0]]; [mh addObject:q[1]]; }
    object_setIvar(grid, wi, [mw copy]);
    object_setIvar(grid, hi, [mh copy]);
}

%group G3B_Orient

// 1.1 consumer (16.2 0x1c76d71d0)
%hook SBMainSwitcherControllerCoordinator
%new
- (void)switcherContentController:(id)controller setInterfaceOrientationFromUserResizing:(long long)o forDisplayItem:(id)item {
    if (!controller || !item || !BP_G3B_On("g3b_orient")) return;
    SEL hs = BPS("switcherContentController:deviceApplicationSceneHandleForDisplayItem:");
    id handle = [self respondsToSelector:hs] ? ((id (*)(id, SEL, id, id))objc_msgSend)(self, hs, controller, item) : nil;
    SEL setter = BPS("_setInterfaceOrientationFromUserResizing:");
    if (!handle || ![handle respondsToSelector:setter]) return;
    id app = BP_G3B_Send0(handle, BPS("application"));
    if (BPG3BO_Bool0(app, BPS("isMedusaCapable"))) return;                         // only classic apps follow the window shape
    id sc = BPG3BO_Obj1(self, BPS("_switcherControllerForContentViewController:"), controller);
    if (!BPG3BO_Bool0(app, BPS("classicAppPhoneAppRunningOnPad"))) {
        id ws = BP_G3B_Send0(sc, BPS("windowScene"));
        if (!BPG3BO_Bool0(ws, BPS("isExternalDisplayWindowScene")) && BP_G3B_SendLL(controller, BPS("contentOrientation")) == o) o = 0;
    }
    ((void (*)(id, SEL, long long))objc_msgSend)(handle, setter, o);
    BPG3BTraitsGuide *g = objc_getAssociatedObject(sc, &kBPG3BGuideKey);
    [g refresh:@"UserResizeOrientation"];
}
%end

// 1.2 producer: wrap the usual response (16.2 0x1c76bed98 ... 0x1c76bf0c8)
%hook SBItemResizeGestureSwitcherModifier
- (id)handleGestureEvent:(id)event {
    BOOL orth = BPG3BO_ItemAllowsOrthogonal(self, BPG3BO_ModifierItem(self));
    if (orth) tBPOrthDepth++;
    id r = %orig;
    if (orth) tBPOrthDepth--;
    return r;
}
- (id)_responseForGestureUpdateAtGestureEnd:(BOOL)end {
    BOOL orth = BPG3BO_ItemAllowsOrthogonal(self, BPG3BO_ModifierItem(self));
    if (orth) tBPOrthDepth++;
    id r = %orig;
    if (orth) tBPOrthDepth--;
    return r;
}
- (id)_responseForSceneSizeUpdateToSize:(CGSize)size center:(CGPoint)center sceneUpdatesOnly:(BOOL)only {
    id item = BPG3BO_ModifierItem(self);
    BOOL orth = BPG3BO_ItemAllowsOrthogonal(self, item);
    if (orth) tBPOrthDepth++;
    id resp = %orig;
    if (orth) tBPOrthDepth--;
    Class rc = NSClassFromString(@"SBSetInterfaceOrientationFromUserResizingEventResponse");     // defined by group1b
    if (!orth || !resp || !rc) return resp;
    long long o = size.width > size.height ? 3 : 1;                                                // UIInterfaceOrientationLandscapeRight : Portrait
    id r = ((id (*)(id, SEL, id, long long))objc_msgSend)([rc alloc], BPS("initWithDisplayItem:desiredContentOrientation:"), item, o);
    if (!r || ![r respondsToSelector:BPS("addChildResponse:")]) return resp;
    ((void (*)(id, SEL, id))objc_msgSend)(r, BPS("addChildResponse:"), resp);
    return r;
}
%end

// 1.3 orthogonal grids: the grid cache is keyed without the orthogonal bit in 16.0, so orthogonal grids live in a private cache
%hook SBDisplayItemLayoutGrid
- (id)_gridForBounds:(CGRect)b contentOrientation:(long long)o layoutRestrictionInfo:(id)info screenScale:(double)s chamoisLayoutAttributes:(id)attrs {
    Ivar iv = class_getInstanceVariable([self class], "_gridCache");
    if (tBPOrthDepth <= 0 || !iv || BPG3BO_ULL0(info, BPS("layoutRestrictions")) != 2 || !BP_G3B_On("g3b_grid")) {
        return %orig;
    }
    id saved = object_getIvar(self, iv);
    NSMutableDictionary *oc = objc_getAssociatedObject(self, &kBPG3BOrthCache);
    if (!oc) { oc = [NSMutableDictionary new]; objc_setAssociatedObject(self, &kBPG3BOrthCache, oc, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    object_setIvar(self, iv, oc);
    tBPOrthBuild++;
    id g = %orig;
    tBPOrthBuild--;
    object_setIvar(self, iv, saved);
    return g;
}
- (void)clearCachedGrids {
    %orig;
    [(NSMutableDictionary *)objc_getAssociatedObject(self, &kBPG3BOrthCache) removeAllObjects];
}
%end

%hook _SBDisplayItemFixedAspectGrid
- (void)_buildFixedGridWithScreenScale:(double)scale {
    %orig;
    if (tBPOrthBuild > 0 && tBPOrthMerge == 0) BPG3BO_MergeTransposed(self, scale);
}
%end

// 1.4 install the guide when the switcher controller sets up its traits participants
%hook SBSwitcherController
- (void)_setupSwitcherTraitsParticipantAndPolicySpecifiers {
    %orig;
    if (!BP_G3B_On("g3b_guide") || objc_getAssociatedObject(self, &kBPG3BGuideKey)) return;
    BPG3BTraitsGuide *g = [BPG3BTraitsGuide new];
    g.switcher = self;
    objc_setAssociatedObject(self, &kBPG3BGuideKey, g, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [g install];
}
%end

// 1.5 handle: 16.2 launch/supported orientation semantics for Medusa-capable apps (the 16.0 "phone app on pad in Stage Manager is portrait" special case is gone)
%hook SBApplication
- (BOOL)classicAppPhoneAppRunningOnPad {
    if (tBPNoPhoneOnPad > 0) return NO;
    return %orig;
}
%end

%hook SBDeviceApplicationSceneHandle
- (long long)_launchingInterfaceOrientationForOrientation:(long long)o {
    id app = BP_G3B_Send0(self, BPS("application"));
    BOOL med = BP_G3B_On("g3b_orient") && BPG3BO_Bool0(app, BPS("isMedusaCapable"));
    if (med) tBPNoPhoneOnPad++;
    long long r = %orig;
    if (med) tBPNoPhoneOnPad--;
    return r;
}
- (unsigned long long)_mainSceneSupportedInterfaceOrientations {
    id app = BP_G3B_Send0(self, BPS("application"));
    if (BP_G3B_On("g3b_orient") && BPG3BO_Bool0(app, BPS("isMedusaCapable"))) return 0x1e;      // 16.2 0x1c72aa11c
    return %orig;
}
%end

%end // G3B_Orient

static void BPG3BO_InstallAdapters(void) {
    if (!BP_G3B_On("g3b_split")) return;
    BPG3BO_AddAdapter("SBSceneViewController");
    BPG3BO_AddAdapter("SBAppContainerViewController");
    BPG3BO_AddAdapter("SBMedusaDecoratedDeviceApplicationSceneViewController");
    {
        Class sh = objc_getClass("SBSceneHandle");
        SEL ns = BPS("newSceneViewWithReferenceSize:contentOrientation:containerOrientation:hostRequester:");
        if (sh && ![sh instancesRespondToSelector:ns]) class_addMethod(sh, ns, (IMP)BPG3BO_NewSceneView, "@56@0:8{CGSize=dd}16q32q40@48");
    }
    // overlay classes conform to the 16.2 overlay protocols when 16.0 has them
    Protocol *pv = NSProtocolFromString(@"SBDeviceApplicationSceneOverlayView"), *pc = NSProtocolFromString(@"SBDeviceApplicationSceneOverlayViewController");
    if (pv) class_addProtocol([SBDeviceApplicationSceneOverlayBasicWrapperView class], pv);
    if (pc) class_addProtocol([SBDeviceApplicationSceneOverlayBasicWrapperViewController class], pc);
}


// ==== SETUP BEGIN
void BP_G3B_Setup(void) {
    %init(G3B_Banner);
    %init(G3B_Menu);
    %init(G3B_Preflight);
    %init(G3B_PiP);
    %init(G3B_KbWindow);
    %init(G3B_StatusBar);
    %init(G3B_AXRoles);
    %init(G3B_Orient);
    BPG3BO_InstallAdapters();
}
// ==== SETUP END
#pragma clang diagnostic pop
