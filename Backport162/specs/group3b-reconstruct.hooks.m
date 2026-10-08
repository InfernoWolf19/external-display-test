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

// ------------------------------------------------------------------------------------------------ host integration
#ifdef BP_G3B_STANDALONE
static void BP_Log(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);
static void BP_Log(NSString *fmt, ...) { (void)fmt; }
#endif

// per-piece switch: on by default, off when <jbroot>/tmp/Backport162.off or Backport162.off.<name> exists
static BOOL BP_G3B_On(const char *name) {
#ifdef BP_G3B_STANDALONE
    (void)name; return YES;
#else
    static char base[1024]; static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *tmp = ROOT_PATH_NS(@"/tmp");
        snprintf(base, sizeof base, "%s/Backport162.off", tmp.fileSystemRepresentation);
    });
    char path[1200];
    if (access(base, F_OK) == 0) return NO;
    snprintf(path, sizeof path, "%s.%s", base, name);
    return access(path, F_OK) != 0;
#endif
}

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
static BOOL BP_G3B_OptIn(const char *name) {
#ifdef BP_G3B_STANDALONE
    (void)name; return NO;
#else
    NSString *tmp = ROOT_PATH_NS(@"/tmp");
    char path[1200]; snprintf(path, sizeof path, "%s/Backport162.on.%s", tmp.fileSystemRepresentation, name);
    return access(path, F_OK) == 0;
#endif
}
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

// ==== SETUP BEGIN
void BP_G3B_Setup(void) {
    %init(G3B_Banner);
    %init(G3B_Menu);
    %init(G3B_Preflight);
    %init(G3B_AXRoles);
}
// ==== SETUP END
#pragma clang diagnostic pop
