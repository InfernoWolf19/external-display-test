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
    objc_setAssociatedObject(p, &kBPG3BPipManagerOfProvider, pipMgr, OBJC_ASSOCIATION_ASSIGN);   // 16.2 +0x48 weak _pipManager
    BP_G3B_SetIvar(self, "_stashTabVisibilityPolicyProvider", p);
}
%end

%hook SBPIPStashTabSuppressionPolicyProvider
// 16.2 0x1c7802b6c: the tap target is registered on the PiP manager of the provider's scene (16.0: the global singleton)
- (void)setStashTabCanBeHidden:(BOOL)canBeHidden {
    id pipMgr = BP_G3B_On("g3b_pip") ? objc_getAssociatedObject(self, &kBPG3BPipManagerOfProvider) : nil;
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

// ==== SETUP BEGIN
void BP_G3B_Setup(void) {
    %init(G3B_Banner);
    %init(G3B_Menu);
    %init(G3B_Preflight);
    %init(G3B_PiP);
    %init(G3B_KbWindow);
    %init(G3B_StatusBar);
    %init(G3B_AXRoles);
}
// ==== SETUP END
#pragma clang diagnostic pop
