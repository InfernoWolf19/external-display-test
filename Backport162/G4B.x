// group4b-reconstruct.hooks.m
//
// DRAFT, Logos source (rename to Group4bReconstruct.x or paste into the Backport162 sources). SpringBoard side of the
// "NOT PORTABLE" pieces of group 4, rebuilt as new code for iPadOS 16.0 (20A8372) from the 16.2 (20C65) disassembly.
// Behaviour and addresses: specs/group4b-reconstruct.md (section numbers in the comments). The backboardd counterpart is
// specs/group4b-backboardd.x (separate Theos target).
//
// One %group per piece so that each can be switched off independently:
//   clonemirror (1)   edu (2)   presubset (3)   deferact (4)   lockedptr2 (5)   migrate (6a)   focuslock (6b)   arrange (7)
// Every group is ON by default; <jbroot>/tmp/Backport162.off.<name> (or Backport162.off) turns it off; tags: DONE / UNSURE.
//
// Integration (nothing in the existing files is edited by this draft):
//   * add the file to Backport162_FILES, keep -fobjc-arc, call G4B_Setup() at the end of the existing %ctor (after BP_BuildMatches()).
//   * pieces that touch the same 16.0 methods as Group4Focus.x are written to cooperate with it (see "COOPERATION" notes).
//   * install order: see the SUMMARY in group4b-reconstruct.md.
//
// House rules (same as the earlier drafts):
//   no hard-coded ivar offsets (ivar_getOffset by name only), private calls guarded (respondsToSelector: / NSClassFromString),
//   nothing dereferenced without a nil check, %orig on its own line, messages to `id` named `type` through objc_msgSend casts,
//   builds with -Wall -Werror (unused statics are silenced by the pragmas below).

#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wunused-variable"

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach/mach.h>
#import <mach/mig.h>
#import <mach-o/dyld.h>
#import <dispatch/dispatch.h>
#import <dlfcn.h>
#import <fcntl.h>
#import <string.h>
#import <unistd.h>
#import <sys/sysctl.h>
#import <UIKit/UIKit.h>
#import "BP.h"

// INTEGRATION: interface declarations for the hooked classes (Logos only emits @class, ARC needs a visible @interface to message them)
@interface SBDisplayAssertionPreferences : NSObject @end
@interface SBSystemShellExtendedDisplayControllerPolicy : NSObject @end
@interface SBNonInteractiveDisplayControllerPolicy : NSObject @end
@interface SBSceneHostingDisplayController : NSObject @end
@interface SBDisplayManager : NSObject @end
@interface SBExternalDisplayDefaults : NSObject @end
@interface SBExternalDisplayEducationObserver : NSObject @end
@interface SpringBoard : NSObject @end
@interface SBSceneManager : NSObject @end
@interface SBMousePointerManager : NSObject @end
@interface _SBDisplayAssertionStack : NSObject @end
@interface SBDisplayAssertionCoordinator : NSObject @end
@interface SBWindowScene : NSObject @end
@interface SBLockedPointerManager : NSObject @end
@interface SBSystemShellExternalDisplaySceneManager : NSObject @end
@interface SBAbstractWindowSceneDelegate : NSObject @end
@interface SBFluidSwitcherViewController : UIViewController @end
@interface SBFluidSwitcherItemContainer : NSObject @end
@interface SBMainSwitcherControllerCoordinator : NSObject @end
@interface SBWorkspaceKeyboardFocusController : NSObject @end
@interface SBExternalDisplaySettings : NSObject @end
@interface SBWindowSceneManager : NSObject @end
@interface SBExternalDisplayService : NSObject @end
// END INTEGRATION interfaces

// default-on switch with off files (Backport162.off, Backport162.off.<name>), cached one second per name
static BOOL G4B_On(const char *name) { return BP_OnName(name); }     // INTEGRATION: shared switches (BP.h)

// opt-in switch: <jbroot>/tmp/Backport162.on.<name>, checked at most once a second
static BOOL G4B_OptIn(const char *name) { return BP_OptInName(name); }

// `type`, `count` ... are declared with different return types in Foundation: message explicitly when needed.
static inline long long G4B_LL(id obj, SEL sel) { return ((long long (*)(id, SEL))objc_msgSend)(obj, sel); }
static inline BOOL G4B_Bool(id obj, SEL sel) { return ((BOOL (*)(id, SEL))objc_msgSend)(obj, sel); }
static inline id G4B_Obj(id obj, SEL sel) { return (obj && [obj respondsToSelector:sel]) ? ((id (*)(id, SEL))objc_msgSend)(obj, sel) : nil; }
static inline id G4B_Obj1(id obj, SEL sel, id a) { return (obj && [obj respondsToSelector:sel]) ? ((id (*)(id, SEL, id))objc_msgSend)(obj, sel, a) : nil; }

// Object ivar by name (never an offset). nil if absent or not an object.
static id G4B_Ivar(id obj, const char *name) {
    if (!obj || !name) return nil;
    Ivar iv = class_getInstanceVariable(object_getClass(obj), name);
    if (!iv) return nil;
    const char *t = ivar_getTypeEncoding(iv);
    if (!t || t[0] != '@') return nil;
    return object_getIvar(obj, iv);
}
// Scalar ivar (BOOL/int/long long...) by name through ivar_getOffset: returns NO if the ivar is missing.
static BOOL G4B_IvarBytes(id obj, const char *name, void *out, size_t size) {
    if (!obj || !name || !out) return NO;
    Ivar iv = class_getInstanceVariable(object_getClass(obj), name);
    if (!iv) return NO;
    memcpy(out, (const char *)(__bridge const void *)obj + ivar_getOffset(iv), size);
    return YES;
}

static void G4B_Main(dispatch_block_t b) {
    if (!b) return;
    if ([NSThread isMainThread]) b(); else dispatch_async(dispatch_get_main_queue(), b);
}

// Associated-object slots
static const void *kG4BKeyA = &kG4BKeyA;
static const void *kG4BKeyB = &kG4BKeyB;
static const void *kG4BKeyC = &kG4BKeyC;
static const void *kG4BKeyD = &kG4BKeyD;

// Informal declarations so that messages to `id` compile without private headers (every selector below exists in the 16.0
// binaries, or is added by a %new method / class in this file).
@interface NSObject (G4BPrivate)
+ (id)sharedInstance;
+ (id)localDefaults;
+ (id)rootSettings;
+ (id)mainWorkspace;
+ (id)uniqueIdentificationForPresentable:(id)p;
- (BOOL)isRootIdentity;
- (BOOL)isMainDisplay;
- (BOOL)isExternal;
- (id)rootIdentity;
- (id)hardwareIdentifier;
- (id)configurationForIdentity:(id)identity;
- (BOOL)extendedDisplayEverEnabledWithHardwareReqsSatisfied;
- (BOOL)extendedDisplayEverEnabledWithoutHardwareReqsSatisfied;
- (id)externalDisplayDefaults;
- (void)setMirroringEnabled:(BOOL)enabled;
- (id)bannerManager;
- (id)initWithBannerPoster:(id)poster;
- (BOOL)_areRuntimeAvailabilityRequirementsMet;
- (unsigned long long)cloneMirroringMode;
- (void)setCloneMirroringMode:(unsigned long long)mode;
- (unsigned long long)bp_cloneMirroringMode;
- (void)_setCloneMirroringMode:(unsigned long long)mode forDisplay:(id)display;
- (void)activateAssertionsForDisplay:(id)display;
- (void)_evalAndApplyOldPreferences:(id)old newPreferences:(id)new_;
- (id)windowSceneManager;
- (id)embeddedDisplayWindowScene;
- (id)activeDisplayWindowScene;
- (id)sceneManager;
- (id)_layoutStateTransitionCoordinator;
- (id)currentLayoutState;
- (id)settings;
- (id)clientSettings;
- (id)identifier;
- (id)windowScene;
- (id)_windowScene;
- (id)_sbWindowScene;
- (id)_fbsDisplayIdentity;
- (id)_fbsDisplayConfiguration;
- (id)allScenes;
- (void)removeObserver:(id)observer;
- (void)addObserver:(id)observer;
- (id)lockedPointerManager;
- (id)initWithWindowScene:(id)ws;
- (void)clientWithSceneIdentifier:(id)sid prefersPointerLockStatus:(long long)status;
- (void)clientWithSceneIdentifier:(id)sid suppressPreferredLockStatus:(BOOL)suppress;
- (void)clientWithSceneIdentifier:(id)sid suppressPreferredPointerLockStatusUpdated:(BOOL)updated;
- (void)_notInvalidated_updateLockForLayoutState:(id)state;
- (void)_updateLockForLayoutState:(id)state;
- (id)_possibleSceneHandleForLockingPointerFromLayoutState:(id)state;
- (BOOL)_queue_prefersLockForSceneIdentifier:(id)sid;
- (BOOL)_shouldAllowPointerLockedForScene:(id)handle;
- (void)_queue_lockPointerForSceneIdentifier:(id)sid;
- (void)_queue_unlockPointer;
- (void)_setPointerLockStatus:(long long)status forSceneWithIdentifier:(id)sid;
- (id)sceneIdentifier;
- (id)sceneIfExists;
- (BOOL)isEffectivelyForeground;
- (BOOL)isUISubclass;
- (long long)deactivationReasons;
- (id)_controlCenterWindow;
- (BOOL)isPresented;
- (id)boundPointerUIScenes;
- (id)switcherController;
- (id)contentViewController;
- (id)liveOverlayForSceneIdentifier:(id)sid;
- (id)_itemContainerForAppLayoutIfExists:(id)layout;
- (id)appLayout;
- (id)itemForLayoutRole:(long long)role;
- (id)uniqueIdentifier;
- (BOOL)isPreferredPointerLockStatusSuppressed;
- (void)setPreferredPointerLockStatusSuppressed:(BOOL)suppressed;
- (BOOL)contentViewBlocksTouches;
- (void)setContentViewBlocksTouches:(BOOL)blocks;
- (BOOL)isSelectable;
- (void)setSelectable:(BOOL)selectable;
- (BOOL)isExternalDisplayWindowScene;
- (id)switcherControllerForWindowScene:(id)ws;
- (id)appLayoutsForSwitcherController:(id)controller;
- (id)allItems;
- (id)_deviceApplicationSceneHandleForDisplayItem:(id)item;
- (id)addKeyboardFocusObserver:(id)observer;
- (void)addActiveDisplayWindowSceneObserver:(id)observer;
- (id)requestFocusStealingForSpringBoardWindow:(id)window forReason:(id)reason;
- (id)lockFocusToSpringBoardWindowScene:(id)scene forReason:(id)reason;
- (unsigned int)edge;
- (double)offset;
- (id)displayIdentity;
- (id)relativeDisplayIdentity;
- (long long)activeDisplayTrackingMethodology;
- (void)setActiveDisplayTrackingMethodology:(long long)m;
- (id)preferredArrangementOfExternalDisplay:(id)display;
- (id)multiDisplayUserInteractionCoordinator;
- (BOOL)_handleAction:(id)action forScene:(id)scene;
- (void)_presentBanner;
- (id)_endpoint;
- (id)error;
- (id)info;
- (id)initWithSceneManager:(id)sm;
- (id)windowSceneForDisplayIdentity:(id)identity;
- (void)addPointerUISceneToPresentationBinder:(id)scene;
- (void)removePointerUISceneFromPresentationBinder:(id)scene;
@end


@protocol G4BInvalidatable <NSObject>
- (void)invalidate;
@end

// ================================================================================================================
// 1. CLONE MIRRORING                                                                          [UNSURE, see md 1.7]
// ================================================================================================================
// 16.2 client function BKSDisplayServicesSetMainDisplayCloneMirroringModeForDestinationDisplay(uuid, mode), re-implemented
// (md 1.1) with a transport that speaks to the NEW backboardd tweak (group4b-backboardd.x) and falls back to the 16.0 BKS
// global call.  Tokens are G4BCloneToken objects (stand-in for the BSSimpleAssertion of 16.2).

@interface G4BCloneRequest : NSObject
@property (nonatomic) unsigned long long mode;
@property (nonatomic, copy) NSString *uuid;
@end
@implementation G4BCloneRequest
@end

@interface G4BCloneToken : NSObject <G4BInvalidatable>
- (instancetype)initWithRequest:(G4BCloneRequest *)r;
@end

static NSMutableDictionary<NSString *, NSMutableArray<G4BCloneRequest *> *> *gG4BReqs;   // 16.2: static dictionary at 0x1da520000+0x9c0
static NSObject *gG4BReqLock;
static int gG4BDaemon = -1;                                                              // -1 unknown, 1 tweak answered, 0 no tweak
static unsigned long long gG4BLegacyMode;                                                // last mode sent through the legacy global API

extern mach_port_t bootstrap_port;
extern kern_return_t bootstrap_look_up(mach_port_t bp, const char *service_name, mach_port_t *sp);

#define G4B_MSG_SET    0x5b9fa0u
#define G4B_MSG_REMOVE 0x5b9fa1u

// returns 1 = daemon tweak handled it, 0 = daemon answered with an error / does not know the id / timeout, -1 = port unavailable
static int G4B_SendCloneMsg(NSString *uuid, unsigned mode, BOOL remove) {
    const char *u = uuid.UTF8String;
    if (!u) return -1;
    size_t ulen = strlen(u) + 1;
    if (ulen < 2 || ulen > 256) return -1;
    mach_port_t svc = MACH_PORT_NULL;
    if (bootstrap_look_up(bootstrap_port, "com.apple.backboard.display.services", &svc) != KERN_SUCCESS || svc == MACH_PORT_NULL) return -1;
    struct {
        mach_msg_header_t Head;
        NDR_record_t NDR;
        uint32_t len;
        char data[256 + 8];
    } req;
    memset(&req, 0, sizeof req);
    uint32_t padded = (uint32_t)((ulen + 3) & ~3u);
    memcpy(req.data, u, ulen);
    if (!remove) memcpy(req.data + padded, &mode, 4);
    req.NDR = NDR_record;
    req.len = (uint32_t)ulen;
    mach_port_t rp = mig_get_reply_port();
    req.Head.msgh_bits = MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, MACH_MSG_TYPE_MAKE_SEND_ONCE);
    req.Head.msgh_size = (mach_msg_size_t)(0x24 + padded + (remove ? 0 : 4));
    req.Head.msgh_remote_port = svc;
    req.Head.msgh_local_port = rp;
    req.Head.msgh_id = remove ? G4B_MSG_REMOVE : G4B_MSG_SET;
    struct { mach_msg_header_t Head; NDR_record_t NDR; kern_return_t RetCode; mach_msg_trailer_t T; char pad[64]; } rep;
    memset(&rep, 0, sizeof rep);
    kern_return_t kr = mach_msg(&req.Head, MACH_SEND_MSG | MACH_RCV_MSG | MACH_SEND_TIMEOUT | MACH_RCV_TIMEOUT,
                                req.Head.msgh_size, (mach_msg_size_t)sizeof rep, rp, 500, MACH_PORT_NULL);
    mach_port_deallocate(mach_task_self(), svc);
    if (kr != KERN_SUCCESS) {
        if (kr == MACH_RCV_TIMED_OUT || kr == MACH_SEND_TIMED_OUT) mig_dealloc_reply_port(rp);
        BP_Log(@"clonemirror: mach_msg kr=0x%x", kr);
        return 0;
    }
    return (rep.Head.msgh_id == req.Head.msgh_id + 100 && rep.RetCode == KERN_SUCCESS) ? 1 : 0;
}

// legacy 16.0 global API; semantic = "disable cloning of EVERY external display"
static void G4B_LegacyGlobal(unsigned long long mode) {
    typedef void (*Fn)(unsigned long long);
    static Fn fn;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ fn = (Fn)dlsym(RTLD_DEFAULT, "BKSDisplayServicesSetCloneMirroringMode"); });
    if (!fn || mode == gG4BLegacyMode) return;
    gG4BLegacyMode = mode;
    fn(mode);
}
static void G4B_LegacyRecompute(void) {                    // caller holds gG4BReqLock
    unsigned long long m = 0;
    for (NSString *k in gG4BReqs) {
        G4BCloneRequest *first = gG4BReqs[k].firstObject;
        if (first && first.mode == 2) { m = 2; break; }
    }
    G4B_LegacyGlobal(m);
}
static void G4B_Transport(NSString *uuid, unsigned long long mode, BOOL remove) {   // caller holds gG4BReqLock
    if (gG4BDaemon != 0) {
        int r = G4B_SendCloneMsg(uuid, (unsigned)mode, remove);
        if (r == 1) { gG4BDaemon = 1; BP_Log(@"clonemirror: daemon %@ %@ mode %llu", remove ? @"remove" : @"set", uuid, mode); return; }
        if (r == 0 && gG4BDaemon == -1) gG4BDaemon = 0;          // first failure with a reachable port: no tweak in backboardd
        if (r == -1) return;                                      // service port not reachable now: do nothing
    }
    G4B_LegacyRecompute();
}

// 16.2 BKSDisplayServicesSetMainDisplayCloneMirroringModeForDestinationDisplay, faithful port.
static id<G4BInvalidatable> G4B_SetCloneModeForDestination(NSString *uuid, unsigned long long mode) {
    if (![uuid isKindOfClass:[NSString class]] || !uuid.length) return nil;      // 16.2 asserts here (BKSDisplayServices.m:0x145)
    static dispatch_once_t once;
    dispatch_once(&once, ^{ gG4BReqs = [NSMutableDictionary dictionary]; gG4BReqLock = [NSObject new]; });
    G4BCloneRequest *req = [G4BCloneRequest new];
    req.uuid = uuid;
    req.mode = mode;
    G4BCloneToken *tok = [[G4BCloneToken alloc] initWithRequest:req];
    @synchronized (gG4BReqLock) {
        NSMutableArray *arr = gG4BReqs[uuid];
        NSUInteger before = arr.count;
        if (!arr) { arr = [NSMutableArray array]; gG4BReqs[uuid] = arr; }
        [arr addObject:req];
        if (before == 0) G4B_Transport(uuid, mode, NO);          // only the first request for a destination is sent
    }
    return tok;
}
static void G4B_InvalidateCloneRequest(G4BCloneRequest *req) {   // block 0x18e4886ec
    if (!req || !gG4BReqLock) return;
    @synchronized (gG4BReqLock) {
        NSMutableArray<G4BCloneRequest *> *arr = gG4BReqs[req.uuid];
        if (![arr containsObject:req]) return;
        unsigned long long oldMode = arr.firstObject.mode;
        [arr removeObject:req];
        G4BCloneRequest *nf = arr.firstObject;
        if (arr.count == 0) { [gG4BReqs removeObjectForKey:req.uuid]; G4B_Transport(req.uuid, 0, YES); }
        else if (oldMode != nf.mode) G4B_Transport(req.uuid, nf.mode, NO);
    }
}

@implementation G4BCloneToken {
    G4BCloneRequest *_req;
}
- (instancetype)initWithRequest:(G4BCloneRequest *)r {
    if ((self = [super init])) _req = r;
    return self;
}
- (void)invalidate {
    G4BCloneRequest *r = nil;
    @synchronized (self) { r = _req; _req = nil; }
    G4B_InvalidateCloneRequest(r);
}
- (void)dealloc { G4B_InvalidateCloneRequest(_req); }               // BSSimpleAssertion invalidates on dealloc as well
@end

%group G4B_Clone

%hook SBDisplayAssertionPreferences
// 16.2 ivar _cloneMirroringMode (0x28, SBDisplayCloneMirroringMode: 0 invalid, 1 default, 2 disabled), kept as an associated object.
%new
- (unsigned long long)cloneMirroringMode {
    return [objc_getAssociatedObject(self, kG4BKeyA) unsignedLongLongValue];
}
%new
- (void)setCloneMirroringMode:(unsigned long long)mode {
    objc_setAssociatedObject(self, kG4BKeyA, mode ? @(mode) : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (id)copyWithZone:(NSZone *)zone {
    id r = %orig;
    if (r && [r respondsToSelector:@selector(setCloneMirroringMode:)])
        ((void (*)(id, SEL, unsigned long long))objc_msgSend)(r, @selector(setCloneMirroringMode:), [self cloneMirroringMode]);
    return r;
}
- (BOOL)isEqual:(id)other {
    BOOL r = %orig;
    if (r && other != self && [other respondsToSelector:@selector(cloneMirroringMode)])
        r = [self cloneMirroringMode] == (unsigned long long)G4B_LL(other, @selector(cloneMirroringMode));
    return r;
}
- (unsigned long long)hash {
    unsigned long long h = %orig;
    return h ^ ([self cloneMirroringMode] * 0x9e3779b97f4a7c15ull);
}
%end

%hook SBSystemShellExtendedDisplayControllerPolicy
// 16.2 assertionPreferencesForDisplay:displayConfiguration: 0x1c77dd1cc: p.cloneMirroringMode = 2 (Disabled)
%new
- (unsigned long long)bp_cloneMirroringMode { return 2; }
%end

%hook SBNonInteractiveDisplayControllerPolicy
// 16.2 0x1c78e9808: p.cloneMirroringMode = 1 (Default)
%new
- (unsigned long long)bp_cloneMirroringMode { return 1; }
%end

%hook SBSceneHostingDisplayController
// 16.0 builds the preferences itself (0x1c5f4a328); 16.2 asks the policy. Equivalent: set the field after %orig.
- (id)_createDisplayAssertionPreferences {
    id p = %orig;
    if (G4B_On("clonemirror") && p && [p respondsToSelector:@selector(setCloneMirroringMode:)]) {
        id policy = G4B_Ivar(self, "_policy");
        unsigned long long m = 0;
        if ([policy respondsToSelector:@selector(bp_cloneMirroringMode)]) m = (unsigned long long)G4B_LL(policy, @selector(bp_cloneMirroringMode));
        ((void (*)(id, SEL, unsigned long long))objc_msgSend)(p, @selector(setCloneMirroringMode:), m);
    }
    return p;
}
%end

%hook SBDisplayManager
// Exact port of 16.2 -_setCloneMirroringMode:forDisplay: (0x1c79917ac). State in associated dictionaries (16.2 ivars 0x58/0x60).
%new
- (void)_setCloneMirroringMode:(unsigned long long)mode forDisplay:(id)display {
    if (!display) return;
    if ([display respondsToSelector:@selector(isRootIdentity)] && !G4B_Bool(display, @selector(isRootIdentity))) return;   // 16.2 NSAssert
    NSMutableDictionary *modes = objc_getAssociatedObject(self, kG4BKeyB);
    NSMutableDictionary *toks = objc_getAssociatedObject(self, kG4BKeyC);
    if (!modes) { modes = [NSMutableDictionary dictionary]; objc_setAssociatedObject(self, kG4BKeyB, modes, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    if (!toks) { toks = [NSMutableDictionary dictionary]; objc_setAssociatedObject(self, kG4BKeyC, toks, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    unsigned long long cur = [modes[display] unsignedLongLongValue];
    if (mode == 0) {
        id<G4BInvalidatable> t = toks[display];
        [toks removeObjectForKey:display];
        [modes removeObjectForKey:display];
        [t invalidate];
        return;
    }
    if (cur == mode) return;
    if (mode != 1 && mode != 2) { BP_Log(@"clonemirror: unexpected mirroring mode %llu", mode); return; }   // 16.2 NSAssert :0x1bd
    modes[display] = @(mode);
    if ([display respondsToSelector:@selector(isMainDisplay)] && G4B_Bool(display, @selector(isMainDisplay))) return;       // 16.2: log only
    id cfg = [self respondsToSelector:@selector(configurationForIdentity:)] ? G4B_Obj1(self, @selector(configurationForIdentity:), display) : nil;
    NSString *hw = [cfg respondsToSelector:@selector(hardwareIdentifier)] ? G4B_Obj(cfg, @selector(hardwareIdentifier)) : nil;
    if (!hw) return;
    unsigned long long bks = (mode == 2) ? 2 : 0;          // SB .Default(1) -> BKS default(0); SB .Disabled(2) -> BKS disableMirroring(2)
    id<G4BInvalidatable> token = G4B_SetCloneModeForDestination(hw, bks);
    id<G4BInvalidatable> old = toks[display];
    if (token) toks[display] = token; else [toks removeObjectForKey:display];
    [old invalidate];
}
// 16.0 delivers the dictionary display -> active SBDisplayAssertionPreferences for all displays in one callback (0x1c64d5608);
// 16.2 calls the per-display delegate. We turn the former into the latter.
- (void)assertionCoordinator:(id)coordinator activeAssertionPreferencesHaveChanged:(id)changed {
    %orig;
    if (!G4B_On("clonemirror")) return;
    NSMutableSet *seen = [NSMutableSet set];
    if ([changed isKindOfClass:[NSDictionary class]]) {
        for (id d in [(NSDictionary *)changed allKeys]) {
            id p = ((NSDictionary *)changed)[d];
            unsigned long long m = [p respondsToSelector:@selector(cloneMirroringMode)] ? (unsigned long long)G4B_LL(p, @selector(cloneMirroringMode)) : 0;
            [self _setCloneMirroringMode:m forDisplay:d];
            [seen addObject:d];
        }
    }
    NSDictionary *modes = objc_getAssociatedObject(self, kG4BKeyB);
    for (id d in [modes allKeys]) if (![seen containsObject:d]) [self _setCloneMirroringMode:0 forDisplay:d];
}
- (void)displayMonitor:(id)monitor willDisconnectIdentity:(id)identity {
    %orig;
    if (G4B_On("clonemirror") && identity) [self _setCloneMirroringMode:0 forDisplay:identity];
}
%end

%end // G4B_Clone

// ----- (item 1 ends; further items are appended below)

// ================================================================================================================
// 2. EDUCATION REWORK                                                                          [UNSURE, md 2.6]
// ================================================================================================================
#import <UIKit/UIKit.h>

static NSString *const kG4BNoteConnect    = @"SBSystemShellExtendedDisplayControllerPolicyConnectNotification";
static NSString *const kG4BNoteDisconnect = @"SBSystemShellExtendedDisplayControllerPolicyDisconnectNotification";
static NSString *const kG4BNoteWindowExp  = @"SBSystemShellExtendedDisplayControllerPolicyDeviceConnectionWindowExpiredNotification";
static NSString *const kG4BNoteHardware   = @"SBSystemShellExtendedDisplayControllerHardwareAvailabilityNotification";
static NSString *const kG4BKeyAvailable   = @"kSBSystemShellExtendedDisplayControllerHardwareAvailabilityIsAvailableKey";
static NSString *const kG4BKeyInWindow    = @"kSBSystemShellExtendedDisplayControllerFiredDuringDeviceConnectionWindowKey";
static NSString *const kG4BKeyIdentity    = @"kSBSystemShellExtendedDisplayControllerDisplayIdentityKey";
static NSString *const kG4BEduDefaultsKey = @"SBExternalDisplayEducationReasons";   // 16.2 SBExternalDisplayDefaults key, md 2.1

// ---- protocols that 16.0 lacks (names as in 16.2)
@protocol SBRemoteHandshakeProtocol
- (void)wakeUpConnection;
@end
@protocol SBExternalDisplayHardwareRequirementsChangedProtocol
- (void)dismissAnimated:(BOOL)animated;
- (void)externalDisplayHardwareRequirementsSatisfiedChanged:(BOOL)changed;
@end
@protocol SBExternalDisplayEducationPillViewControllerDelegate <NSObject>
- (void)pillViewControllerDidReceiveUserTap:(id)tap;
@end

// ---- defaults shim (md 2.1)
static unsigned long long G4B_EduReasonsRead(id defaults) {
    CFPropertyListRef v = CFPreferencesCopyAppValue((__bridge CFStringRef)kG4BEduDefaultsKey, CFSTR("com.apple.springboard"));
    if (v) {
        unsigned long long r = 0;
        if (CFGetTypeID(v) == CFNumberGetTypeID()) CFNumberGetValue(v, kCFNumberLongLongType, &r);
        CFRelease(v);
        return r;
    }
    unsigned long long m = 0;     // migrate from the 16.0 booleans
    if ([defaults respondsToSelector:@selector(extendedDisplayEverEnabledWithHardwareReqsSatisfied)] &&
        G4B_Bool(defaults, @selector(extendedDisplayEverEnabledWithHardwareReqsSatisfied))) m |= 1;
    if ([defaults respondsToSelector:@selector(extendedDisplayEverEnabledWithoutHardwareReqsSatisfied)] &&
        G4B_Bool(defaults, @selector(extendedDisplayEverEnabledWithoutHardwareReqsSatisfied))) m |= 2;
    return m;
}
static void G4B_EduReasonsWrite(unsigned long long r) {
    CFPreferencesSetAppValue((__bridge CFStringRef)kG4BEduDefaultsKey, (__bridge CFNumberRef)@(r), CFSTR("com.apple.springboard"));
    CFPreferencesAppSynchronize(CFSTR("com.apple.springboard"));
}
static id G4B_ExternalDisplayDefaults(void) {
    Class k = NSClassFromString(@"SBDefaults");
    id ld = [k respondsToSelector:@selector(localDefaults)] ? G4B_Obj((id)k, @selector(localDefaults)) : nil;
    return [ld respondsToSelector:@selector(externalDisplayDefaults)] ? G4B_Obj(ld, @selector(externalDisplayDefaults)) : nil;
}
static void G4B_EduSetReasons(unsigned long long r) { G4B_EduReasonsWrite(r); }

// ---- native fallback alert (md 2.6) --------------------------------------------------------------------------
static UIWindow *gG4BNativeWindow;
static void G4B_NativeAlert(BOOL hardwareInWindow, void (^done)(NSUInteger result)) {
    G4B_Main(^{
        id wsm = [[UIApplication sharedApplication] respondsToSelector:@selector(windowSceneManager)] ? G4B_Obj([UIApplication sharedApplication], @selector(windowSceneManager)) : nil;
        id scene = [wsm respondsToSelector:@selector(embeddedDisplayWindowScene)] ? G4B_Obj(wsm, @selector(embeddedDisplayWindowScene)) : nil;
        if (![scene isKindOfClass:[UIWindowScene class]]) { done(0); return; }
        UIWindow *w = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
        w.windowLevel = UIWindowLevelAlert + 10;
        w.rootViewController = [UIViewController new];
        w.hidden = NO;
        gG4BNativeWindow = w;
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"External Display"
            message:hardwareInWindow ? @"A keyboard and pointer are connected. Use this display as an extended display?" : @"Use this display as an extended display? Connect a keyboard and pointer to use it fully."
            preferredStyle:UIAlertControllerStyleAlert];
        void (^finish)(NSUInteger) = ^(NSUInteger r) { gG4BNativeWindow.hidden = YES; gG4BNativeWindow = nil; done(r); };
        [a addAction:[UIAlertAction actionWithTitle:@"Extended Display" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { finish(1); }]];
        [a addAction:[UIAlertAction actionWithTitle:@"Mirror" style:UIAlertActionStyleCancel handler:^(UIAlertAction *x) { finish(2); }]];
        [w.rootViewController presentViewController:a animated:YES completion:nil];
    });
}

// ---- pill view controller (md 2.4) ---------------------------------------------------------------------------
@interface SBExternalDisplayEducationPillViewController : UIViewController {
    BOOL _extendedDisplayEnabled;
    UIView *_pillView;
    __weak id<SBExternalDisplayEducationPillViewControllerDelegate> _delegate;
}
@property (nonatomic, weak) id<SBExternalDisplayEducationPillViewControllerDelegate> delegate;
@property (nonatomic, weak) id presentableContext;
- (instancetype)initWithExtendedDisplayEnabled:(BOOL)enabled;
- (void)updateExtendedDisplayEnabled:(BOOL)enabled;
@end

static NSString *G4B_SymString(const char *n) {            // exported NSString* constant of SpringBoard
    void *p = dlsym(RTLD_DEFAULT, n);
    return p ? *(__unsafe_unretained NSString *const *)p : nil;
}
static NSString *G4B_Localized(NSString *key, NSString *fallback) {
    NSString *s = [[NSBundle mainBundle] localizedStringForKey:key value:@"" table:nil];
    return (s.length && ![s isEqualToString:key]) ? s : fallback;
}

@implementation SBExternalDisplayEducationPillViewController
@synthesize delegate = _delegate;
- (instancetype)initWithExtendedDisplayEnabled:(BOOL)enabled {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _extendedDisplayEnabled = enabled;
        [self loadViewIfNeeded];
        if ([_pillView respondsToSelector:@selector(intrinsicContentSize)]) self.preferredContentSize = [_pillView intrinsicContentSize];
    }
    return self;
}
- (id)_pillSubtitleContentItem {
    Class ci = NSClassFromString(@"PLPillContentItem");
    NSString *t = _extendedDisplayEnabled ? G4B_Localized(@"STAGE_MANAGER_EXTENDED_DISPLAY_ON", @"On") : G4B_Localized(@"STAGE_MANAGER_EXTENDED_DISPLAY_OFF", @"Off");
    return ((id (*)(id, SEL, id, long long))objc_msgSend)([ci alloc], NSSelectorFromString(@"initWithText:style:"), t, 2);
}
- (void)viewDidLoad {
    [super viewDidLoad];
    Class pill = NSClassFromString(@"PLPillView"), ci = NSClassFromString(@"PLPillContentItem");
    if (!pill || !ci) return;
    UIView *host = self.view;
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithHierarchicalColor:[UIColor labelColor]];
    UIImageView *lead = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"display" withConfiguration:cfg]];
    UIImageView *trail = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"]];
    NSString *title = G4B_Localized(@"STAGE_MANAGER_EXTENDED_DISPLAY", @"Extended Display");
    UIView *pv = ((id (*)(id, SEL, id, id))objc_msgSend)([pill alloc], NSSelectorFromString(@"initWithLeadingAccessoryView:trailingAccessoryView:"), lead, trail);
    _pillView = pv;
    id titleItem = ((id (*)(id, SEL, id, long long))objc_msgSend)([ci alloc], NSSelectorFromString(@"initWithText:style:"), title, 1);
    id sub = [self _pillSubtitleContentItem];
    if (titleItem && sub) ((void (*)(id, SEL, id))objc_msgSend)(pv, NSSelectorFromString(@"setCenterContentItems:"), @[titleItem, sub]);
    pv.frame = host.bounds;
    pv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [host addSubview:pv];
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_handleSingleTap:)];
    tap.numberOfTouchesRequired = 1;
    tap.numberOfTapsRequired = 1;
    [host addGestureRecognizer:tap];
}
- (void)updateExtendedDisplayEnabled:(BOOL)enabled {
    if (_extendedDisplayEnabled == enabled) return;
    _extendedDisplayEnabled = enabled;
    SEL c = NSSelectorFromString(@"centerContentItems"), u = NSSelectorFromString(@"updateCenterContentItem:withContentItem:");
    if (![_pillView respondsToSelector:c] || ![_pillView respondsToSelector:u]) return;
    NSArray *items = G4B_Obj(_pillView, c);
    if (items.count < 2) return;
    ((void (*)(id, SEL, id, id))objc_msgSend)(_pillView, u, items[1], [self _pillSubtitleContentItem]);
}
- (void)_handleSingleTap:(id)tap { [_delegate pillViewControllerDidReceiveUserTap:self]; }
// BNPresentable / BNPresentableIdentifying (protocols attached at runtime in G4B_Setup)
- (NSString *)requestIdentifier { return @"ExternalDisplayEducation"; }
- (NSString *)requesterIdentifier { return @"com.apple.SpringBoard.ExternalDisplayEducation"; }
- (NSString *)presentableDescription { return @"External Display Education"; }
- (long long)presentableBehavior { return 1; }
- (UIViewController *)viewController { return self; }
- (void)addPresentableObserver:(id)o {}
- (void)removePresentableObserver:(id)o {}
@end

// ---- session (md 2.3) ----------------------------------------------------------------------------------------
@interface SBExternalDisplayEducationSession : NSObject <SBExternalDisplayEducationPillViewControllerDelegate, SBRemoteHandshakeProtocol, NSXPCListenerDelegate> {
    id _displayIdentity;
    BOOL _disconnected;
    BOOL _isHardwareAvailable;
    BOOL _isHardwareAvailableDuringDisplayConnectionWindow;
    id _bannerPoster;
    unsigned long long _previousPresentedReasons;
    BOOL _isPresenting;
    id _alertHandle;
    NSXPCConnection *_xpcConnection;
    NSXPCListener *_listener;
    SBExternalDisplayEducationPillViewController *_educationBannerViewController;
    NSUInteger _bannerGeneration;
}
@property (nonatomic, readonly) id displayIdentity;
- (instancetype)initWithDisplayIdentity:(id)ident hardwareAvailability:(BOOL)hw bannerPoster:(id)poster;
- (void)displayConnected;
- (void)displayDisconnected;
- (void)deviceConnectionWindowExpired;
- (void)updateHardwareAvailability:(BOOL)avail withinDisplayConnectionWindow:(BOOL)inWindow;
@end

@implementation SBExternalDisplayEducationSession
@synthesize displayIdentity = _displayIdentity;
- (instancetype)initWithDisplayIdentity:(id)ident hardwareAvailability:(BOOL)hw bannerPoster:(id)poster {
    if ((self = [super init])) {
        _displayIdentity = ident;
        _isHardwareAvailable = hw;
        _isHardwareAvailableDuringDisplayConnectionWindow = hw;
        _bannerPoster = poster;
        _previousPresentedReasons = G4B_EduReasonsRead(G4B_ExternalDisplayDefaults());
        BP_Log(@"edu: creating session with previous reasons: %llu", _previousPresentedReasons);
    }
    return self;
}
- (void)dealloc { [_listener invalidate]; [_xpcConnection invalidate]; }

- (void)_recordReason:(unsigned long long)bit {     // alert completion blocks 0x37b8 / 0x3978 / 0x3e8c / 0x4238
    unsigned long long r = G4B_EduReasonsRead(G4B_ExternalDisplayDefaults());
    G4B_EduSetReasons(r | bit);
}
- (void)displayConnected {
    BP_Log(@"edu: display connected");
    unsigned long long reasons = _previousPresentedReasons;
    __weak typeof(self) ws = self;
    if (reasons == 0) {
        BP_Log(@"edu: not presented either alert before, presenting now");
        [self _presentEducationAlert:^(NSUInteger ok) { typeof(self) s = ws; if (ok && s) [s _recordReason:s->_isHardwareAvailableDuringDisplayConnectionWindow ? 1 : 2]; }];
    } else if (_isHardwareAvailableDuringDisplayConnectionWindow) {
        if (reasons & 1) [self _presentBanner];
        else [self _presentEducationAlert:^(NSUInteger ok) { typeof(self) s = ws; if (ok && s) [s _recordReason:1]; }];
    } else if (reasons == 3) {
        [self _presentBanner];
    }
}
- (void)deviceConnectionWindowExpired {
    BP_Log(@"edu: device connection window expired");
    if (_isHardwareAvailableDuringDisplayConnectionWindow || _isPresenting) return;
    __weak typeof(self) ws = self;
    if (_previousPresentedReasons & 2) [self _presentBanner];
    else [self _presentEducationAlert:^(NSUInteger ok) { typeof(self) s = ws; if (ok && s) [s _recordReason:2]; }];
}
- (void)updateHardwareAvailability:(BOOL)avail withinDisplayConnectionWindow:(BOOL)inWindow {
    if (!_isHardwareAvailable && !avail) return;
    _isHardwareAvailable = avail;
    if (inWindow && !_isHardwareAvailableDuringDisplayConnectionWindow) _isHardwareAvailableDuringDisplayConnectionWindow = avail;
    __weak typeof(self) ws = self;
    if (_isHardwareAvailableDuringDisplayConnectionWindow && !_isPresenting) {
        if (!(_previousPresentedReasons & 1))
            [self _presentEducationAlert:^(NSUInteger ok) { typeof(self) s = ws; if (ok && s && s->_isHardwareAvailableDuringDisplayConnectionWindow) [s _recordReason:1]; }];
        else [self _presentBanner];
    } else if (_isPresenting) {
        if (_xpcConnection) {
            id proxy = [_xpcConnection remoteObjectProxy];
            if ([proxy respondsToSelector:@selector(externalDisplayHardwareRequirementsSatisfiedChanged:)])
                [(id<SBExternalDisplayHardwareRequirementsChangedProtocol>)proxy externalDisplayHardwareRequirementsSatisfiedChanged:_isHardwareAvailable];
        } else if (_educationBannerViewController) {
            [_educationBannerViewController updateExtendedDisplayEnabled:_isHardwareAvailableDuringDisplayConnectionWindow];
        }
    }
}
- (void)displayDisconnected {
    _disconnected = YES;
    BP_Log(@"edu: display disconnected");
    if (_isPresenting) {
        [self _dismissEducationAlert:@"Display Disconnected"];
        [self _dismissBanner:@"Display Disconnected"];
    }
}

- (void)_presentEducationAlert:(void (^)(NSUInteger))completion {
    if (!completion || _isPresenting) { BP_Log(@"edu: refusing second presentation"); return; }    // 16.2 NSAssert
    _isPresenting = YES;
    BOOL hwInWindow = _isHardwareAvailableDuringDisplayConnectionWindow;
    void (^complete)(NSUInteger) = ^(NSUInteger result) {
        if (result) {                                     // the session writes the mirroring default itself (0x1c77d4ab8)
            id d = G4B_ExternalDisplayDefaults();
            if ([d respondsToSelector:@selector(setMirroringEnabled:)])
                ((void (*)(id, SEL, BOOL))objc_msgSend)(d, @selector(setMirroringEnabled:), result == 2);
        }
        BP_Log(@"edu: received response from user. externalDisplayEnabled: %d", result == 1);
        completion(result);
    };
    if (G4B_OptIn("edunative")) { G4B_NativeAlert(hwInWindow, complete); return; }       // opt-in fallback, md 2.6

    Class defC = NSClassFromString(@"SBSRemoteAlertDefinition"), cfgC = NSClassFromString(@"SBSRemoteAlertConfigurationContext");
    Class handleC = NSClassFromString(@"SBSRemoteAlertHandle"), actC = NSClassFromString(@"SBSRemoteAlertActivationContext");
    Class actionC = NSClassFromString(@"BSAction"), respC = NSClassFromString(@"BSActionResponder");
    if (!defC || !cfgC || !handleC || !actC || !actionC || !respC) { _isPresenting = NO; complete(0); return; }
    _listener = [NSXPCListener anonymousListener];
    _listener.delegate = self;
    [_listener resume];     // INTEGRATION: -activate is not in the iOS SDK headers; -resume is the 16.0 API
    id def = ((id (*)(id, SEL, id, id))objc_msgSend)([defC alloc], NSSelectorFromString(@"initWithServiceName:viewControllerClassName:"), @"com.apple.SpringBoardEducation", @"SBERemoteViewController");
    ((void (*)(id, SEL, BOOL))objc_msgSend)(def, NSSelectorFromString(@"setPrefersEmbeddedDisplayPresentation:"), YES);
    id cfg = [[cfgC alloc] init];
    id ep = [[_listener endpoint] respondsToSelector:@selector(_endpoint)] ? G4B_Obj([_listener endpoint], @selector(_endpoint)) : nil;
    if (ep) ((void (*)(id, SEL, id))objc_msgSend)(cfg, NSSelectorFromString(@"setXpcEndpoint:"), ep);
    _alertHandle = ((id (*)(id, SEL, id, id))objc_msgSend)((id)handleC, NSSelectorFromString(@"newHandleWithDefinition:configurationContext:"), def, cfg);
    id act = [[actC alloc] init];
    NSString *kType = G4B_SymString("SBEducationRemoteViewControllerEducationTypeKey");
    NSString *kHw = G4B_SymString("SBEducationRemoteViewControllerHasPointerAndKeyboardConnectedKey");
    if (kType && kHw) ((void (*)(id, SEL, id))objc_msgSend)(act, NSSelectorFromString(@"setUserInfo:"), @{ kType: @1, kHw: @(hwInWindow) });
    id responder = ((id (*)(id, SEL, id))objc_msgSend)((id)respC, NSSelectorFromString(@"responderWithHandler:"), ^(id response) {
        NSUInteger result = 0;
        if (![response respondsToSelector:@selector(error)] || !G4B_Obj(response, @selector(error))) {
            id info = [response respondsToSelector:@selector(info)] ? G4B_Obj(response, @selector(info)) : nil;
            long long flag = [info respondsToSelector:NSSelectorFromString(@"flagForSetting:")]
                ? ((long long (*)(id, SEL, unsigned long long))objc_msgSend)(info, NSSelectorFromString(@"flagForSetting:"), 1) : LLONG_MAX;
            result = (flag == LLONG_MAX) ? 0 : (flag == 0 ? 2 : 1);     // flag NO -> user chose mirroring (2), YES -> extended (1)
        }
        complete(result);
    });
    ((void (*)(id, SEL, id))objc_msgSend)(responder, NSSelectorFromString(@"setQueue:"), dispatch_get_main_queue());
    id action = ((id (*)(id, SEL, id, id))objc_msgSend)([actionC alloc], NSSelectorFromString(@"initWithInfo:responder:"), nil, responder);
    if (action) ((void (*)(id, SEL, id))objc_msgSend)(act, NSSelectorFromString(@"setActions:"), [NSSet setWithObject:action]);
    ((void (*)(id, SEL, id))objc_msgSend)(_alertHandle, NSSelectorFromString(@"activateWithContext:"), act);
}
- (BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)c {
    if (_disconnected) return NO;
    c.exportedObject = self;
    c.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SBRemoteHandshakeProtocol)];
    c.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SBExternalDisplayHardwareRequirementsChangedProtocol)];
    [c resume];
    _xpcConnection = c;
    BP_Log(@"edu: client connected");
    return YES;
}
- (void)wakeUpConnection {}
- (void)_dismissEducationAlert:(NSString *)reason {
    if (_xpcConnection) {
        BP_Log(@"edu: dismissing alert for reason: %@ via xpcConnection", reason);
        [(id<SBExternalDisplayHardwareRequirementsChangedProtocol>)[_xpcConnection remoteObjectProxy] dismissAnimated:YES];
    } else if (_alertHandle) {
        BP_Log(@"edu: dismissing alert for reason: %@ via alertHandle", reason);
        if ([_alertHandle respondsToSelector:@selector(invalidate)]) [(id<G4BInvalidatable>)_alertHandle invalidate];
    }
    if (gG4BNativeWindow) { gG4BNativeWindow.hidden = YES; gG4BNativeWindow = nil; }
}
- (void)_presentBanner {
    if (_isPresenting) { BP_Log(@"edu: refusing second presentation"); return; }
    _isPresenting = YES;
    _educationBannerViewController = [[SBExternalDisplayEducationPillViewController alloc] initWithExtendedDisplayEnabled:_isHardwareAvailableDuringDisplayConnectionWindow];
    _educationBannerViewController.delegate = self;
    NSError *err = nil;
    SEL post = NSSelectorFromString(@"postPresentable:withOptions:userInfo:error:");
    if ([_bannerPoster respondsToSelector:post])
        ((id (*)(id, SEL, id, unsigned long long, id, NSError **))objc_msgSend)(_bannerPoster, post, _educationBannerViewController, 1, nil, &err);
    if (err) BP_Log(@"edu: error while presenting education banner: %@", err);
    NSUInteger gen = ++_bannerGeneration;                       // BSAbsoluteMachTimer 3.0 s, leeway 0.05
    __weak typeof(self) ws = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        typeof(self) s = ws;
        if (s && s->_bannerGeneration == gen) [s _dismissBanner:@"Timer"];
    });
}
- (void)_dismissBanner:(NSString *)reason {
    SBExternalDisplayEducationPillViewController *vc = _educationBannerViewController;
    if (!vc) return;
    Class idc = NSClassFromString(@"BNPresentableIdentification");
    SEL uid = NSSelectorFromString(@"uniqueIdentificationForPresentable:"), rev = NSSelectorFromString(@"revokePresentablesWithIdentification:reason:options:userInfo:error:");
    if ([(id)idc respondsToSelector:uid] && [_bannerPoster respondsToSelector:rev]) {
        id ident = G4B_Obj1((id)idc, uid, vc);
        ((id (*)(id, SEL, id, id, unsigned long long, id, NSError **))objc_msgSend)(_bannerPoster, rev, ident, reason, 0, nil, NULL);
    }
}
- (void)pillViewControllerDidReceiveUserTap:(id)tap {
    _bannerGeneration++;                                         // invalidates the dismiss timer
    [self _dismissBanner:@"User Interaction"];
    NSURL *url = [NSURL URLWithString:@"prefs:root=DISPLAY&path=DISPLAY_ARRANGEMENT"];
    typedef void (*ActFn)(NSURL *, id);
    ActFn act = (ActFn)dlsym(RTLD_DEFAULT, "SBWorkspaceActivateApplicationFromURL");
    if (act) act(url, nil);
    else [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}
@end

// ---- passive producer of the four policy notifications (md 2.2) ----------------------------------------------
@interface G4BPolicyNoteState : NSObject
@property (nonatomic) BOOL windowOpen;
@property (nonatomic) BOOL disconnected;
@property (nonatomic) NSUInteger generation;
@property (nonatomic, strong) id identity;
@end
@implementation G4BPolicyNoteState
@end

static NSString *G4B_KeyboardNoteName(void) {
    static NSString *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ void *p = dlsym(RTLD_DEFAULT, "SBHardwareKeyboardAvailabilityChangedNotification"); if (p) s = *(__unsafe_unretained NSString *const *)p; });
    return s;
}
static void G4B_PostPolicyNote(id policy, NSString *name, NSDictionary *extra) {
    G4BPolicyNoteState *st = objc_getAssociatedObject(policy, kG4BKeyD);
    NSMutableDictionary *ui = [NSMutableDictionary dictionary];
    if (st.identity) ui[kG4BKeyIdentity] = st.identity;
    if (extra) [ui addEntriesFromDictionary:extra];
    [[NSNotificationCenter defaultCenter] postNotificationName:name object:policy userInfo:ui];
}
static void G4B_PolicyHardwareChanged(id policy) {
    G4BPolicyNoteState *st = objc_getAssociatedObject(policy, kG4BKeyD);
    if (!st || st.disconnected || ![policy respondsToSelector:@selector(_areRuntimeAvailabilityRequirementsMet)]) return;
    BOOL met = G4B_Bool(policy, @selector(_areRuntimeAvailabilityRequirementsMet));
    G4B_PostPolicyNote(policy, kG4BNoteHardware, @{ kG4BKeyAvailable: @(met), kG4BKeyInWindow: @(st.windowOpen) });
}

%group G4B_Edu

%hook SBExternalDisplayDefaults
%new
- (unsigned long long)externalDisplayEducationReasons { return G4B_EduReasonsRead(self); }
%new
- (void)setExternalDisplayEducationReasons:(unsigned long long)reasons { G4B_EduReasonsWrite(reasons); }
// Makes the stock 16.0 launch code skip the OLD observer + its BSSimpleAssertion (0x1c5ed78b0), see md 2.2.
- (BOOL)hasShownAllExtendedDisplayEducations {
    if (G4B_On("edu")) return YES;
    return %orig;
}
%end

%hook SBExternalDisplayEducationObserver
%new
- (id)initWithBannerPoster:(id)poster {
    self = [self init];
    if (self) {
        objc_setAssociatedObject(self, kG4BKeyA, poster, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserver:self selector:@selector(_extendedDisplayControllerDidConnect:) name:kG4BNoteConnect object:nil];
        [nc addObserver:self selector:@selector(_extendedDisplayControllerDidDisconnect:) name:kG4BNoteDisconnect object:nil];
        [nc addObserver:self selector:@selector(_deviceConnectionWindowExpired:) name:kG4BNoteWindowExp object:nil];
        [nc addObserver:self selector:@selector(_hardwareAvailabilityChanged:) name:kG4BNoteHardware object:nil];
    }
    return self;
}
%new
- (void)_extendedDisplayControllerDidConnect:(NSNotification *)n {
    id ident = n.userInfo[kG4BKeyIdentity];
    NSNumber *avail = n.userInfo[kG4BKeyAvailable];
    if (!ident || !avail) { BP_Log(@"edu: connect without identity/availability"); return; }
    if (objc_getAssociatedObject(self, kG4BKeyB)) { BP_Log(@"edu: already tracking a session"); return; }
    SBExternalDisplayEducationSession *s = [[SBExternalDisplayEducationSession alloc] initWithDisplayIdentity:ident hardwareAvailability:avail.boolValue bannerPoster:objc_getAssociatedObject(self, kG4BKeyA)];
    objc_setAssociatedObject(self, kG4BKeyB, s, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [s displayConnected];
}
%new
- (void)_extendedDisplayControllerDidDisconnect:(NSNotification *)n {
    SBExternalDisplayEducationSession *s = objc_getAssociatedObject(self, kG4BKeyB);
    if (!n.userInfo[kG4BKeyIdentity] || !s) return;
    [s displayDisconnected];
    objc_setAssociatedObject(self, kG4BKeyB, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
%new
- (void)_deviceConnectionWindowExpired:(NSNotification *)n {
    SBExternalDisplayEducationSession *s = objc_getAssociatedObject(self, kG4BKeyB);
    if (!n.userInfo[kG4BKeyIdentity] || !s) return;
    [s deviceConnectionWindowExpired];
}
%new
- (void)_hardwareAvailabilityChanged:(NSNotification *)n {
    SBExternalDisplayEducationSession *s = objc_getAssociatedObject(self, kG4BKeyB);
    id ident = n.userInfo[kG4BKeyIdentity];
    NSNumber *avail = n.userInfo[kG4BKeyAvailable], *inWin = n.userInfo[kG4BKeyInWindow];
    if (!s || !ident || !avail || !inWin || ![s.displayIdentity isEqual:ident]) return;
    [s updateHardwareAvailability:avail.boolValue withinDisplayConnectionWindow:inWin.boolValue];
}
- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    %orig;
}
%end

%hook SpringBoard
- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    if (!G4B_On("edu")) return;
    Class oc = NSClassFromString(@"SBExternalDisplayEducationObserver");
    id poster = [self respondsToSelector:@selector(bannerManager)] ? G4B_Obj(self, @selector(bannerManager)) : nil;
    if (!oc || !poster || ![oc instancesRespondToSelector:@selector(initWithBannerPoster:)]) return;
    id obs = ((id (*)(id, SEL, id))objc_msgSend)([oc alloc], @selector(initWithBannerPoster:), poster);
    objc_setAssociatedObject(self, kG4BKeyC, obs, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
%end

%hook SBSystemShellExtendedDisplayControllerPolicy
- (void)connectToDisplayController:(id)controller displayConfiguration:(id)config {
    %orig;
    if (!G4B_On("edu") || objc_getAssociatedObject(self, kG4BKeyD)) return;
    G4BPolicyNoteState *st = [G4BPolicyNoteState new];
    id ident = G4B_Ivar(self, "_displayIdentity");
    st.identity = [ident respondsToSelector:@selector(rootIdentity)] ? G4B_Obj(ident, @selector(rootIdentity)) : ident;
    st.windowOpen = YES;
    objc_setAssociatedObject(self, kG4BKeyD, st, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    BOOL met = [self respondsToSelector:@selector(_areRuntimeAvailabilityRequirementsMet)] ? G4B_Bool(self, @selector(_areRuntimeAvailabilityRequirementsMet)) : NO;
    NSString *kn = G4B_KeyboardNoteName();
    if (kn) [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_bp_keyboardAvailabilityChanged:) name:kn object:nil];
    id mgr = G4B_Ivar(self, "_mousePointerManager");
    if ([mgr respondsToSelector:@selector(addObserver:)]) ((void (*)(id, SEL, id))objc_msgSend)(mgr, @selector(addObserver:), self);
    G4B_PostPolicyNote(self, kG4BNoteConnect, @{ kG4BKeyAvailable: @(met), kG4BKeyInWindow: @YES });
    NSUInteger gen = st.generation;
    __weak id wself = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{      // BSContinuousMachTimer 4.0 s
        id s = wself; G4BPolicyNoteState *t = objc_getAssociatedObject(s, kG4BKeyD);
        if (!s || !t || t.disconnected || t.generation != gen) return;
        t.windowOpen = NO;
        G4B_PostPolicyNote(s, kG4BNoteWindowExp, nil);
    });
}
%new
- (void)_bp_keyboardAvailabilityChanged:(NSNotification *)n { G4B_PolicyHardwareChanged(self); }
// SBMousePointerHardwareConnectionObserver (16.2 conformance); sent only if the manager honours optional methods
%new
- (void)mousePointerManager:(id)mgr hardwarePointingDeviceAttachedDidChange:(BOOL)attached { G4B_PolicyHardwareChanged(self); }
- (void)displayControllerDidDisconnect:(id)controller sceneManager:(id)sceneManager {
    G4BPolicyNoteState *st = objc_getAssociatedObject(self, kG4BKeyD);
    if (st && !st.disconnected) {
        st.disconnected = YES; st.windowOpen = NO; st.generation++;
        NSString *kn = G4B_KeyboardNoteName();
        if (kn) [[NSNotificationCenter defaultCenter] removeObserver:self name:kn object:nil];
        id mgr = G4B_Ivar(self, "_mousePointerManager");
        if ([mgr respondsToSelector:@selector(removeObserver:)]) ((void (*)(id, SEL, id))objc_msgSend)(mgr, @selector(removeObserver:), self);
        G4B_PostPolicyNote(self, kG4BNoteDisconnect, nil);
    }
    %orig;
}
%end

%end // G4B_Edu

// ----- (item 2 ends)

// ================================================================================================================
// 3. PRESENTATION-UPDATE SCENE SUBSET                                                                     [DONE]
// ================================================================================================================
static id G4B_SceneManagerForScene(id scene) {
    id settings = [scene respondsToSelector:@selector(settings)] ? G4B_Obj(scene, @selector(settings)) : nil;
    SEL ds = NSSelectorFromString(@"sb_displayIdentityForSceneManagers");
    id ident = [settings respondsToSelector:ds] ? G4B_Obj(settings, ds) : nil;
    Class cc = NSClassFromString(@"SBSceneManagerCoordinator");
    id coord = [(id)cc respondsToSelector:@selector(sharedInstance)] ? G4B_Obj((id)cc, @selector(sharedInstance)) : nil;
    SEL fm = NSSelectorFromString(@"sceneManagerForDisplayIdentity:");
    return (ident && [coord respondsToSelector:fm]) ? G4B_Obj1(coord, fm, ident) : nil;
}
static NSHashTable *G4B_PointerScenes(id sceneManager, BOOL create) {
    NSHashTable *t = objc_getAssociatedObject(sceneManager, kG4BKeyA);
    if (!t && create) { t = [NSHashTable weakObjectsHashTable]; objc_setAssociatedObject(sceneManager, kG4BKeyA, t, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    return t;
}

%group G4B_PreSubset

%hook SBSceneManager
%new
- (id)boundPointerUIScenes { return [NSSet setWithArray:[G4B_PointerScenes(self, NO) allObjects] ?: @[]]; }
%new
- (void)addPointerUISceneToPresentationBinder:(id)scene { if (scene) [G4B_PointerScenes(self, YES) addObject:scene]; }
%new
- (void)removePointerUISceneFromPresentationBinder:(id)scene { if (scene) [G4B_PointerScenes(self, NO) removeObject:scene]; }
%end

%hook SBMousePointerManager
- (void)pointerClientController:(id)controller sceneDidActivate:(id)scene {
    %orig;
    if (!G4B_On("presubset")) return;
    id sm = G4B_SceneManagerForScene(scene);
    if ([sm respondsToSelector:@selector(addPointerUISceneToPresentationBinder:)]) ((void (*)(id, SEL, id))objc_msgSend)(sm, @selector(addPointerUISceneToPresentationBinder:), scene);
}
- (void)pointerClientController:(id)controller sceneWillDeactivate:(id)scene {
    if (G4B_On("presubset")) {
        id sm = G4B_SceneManagerForScene(scene);
        if ([sm respondsToSelector:@selector(removePointerUISceneFromPresentationBinder:)]) ((void (*)(id, SEL, id))objc_msgSend)(sm, @selector(removePointerUISceneFromPresentationBinder:), scene);
    }
    %orig;
}
%end

%hook SBSystemShellExtendedDisplayControllerPolicy
- (void)displayController:(id)controller updatePresentationWithSceneManager:(id)sm displayConfiguration:(id)cfg completion:(void (^)(void))completion {
    if (!G4B_On("presubset") || !sm) {
        %orig;
        return;
    }
    NSMutableSet *scenes = [NSMutableSet set];
    NSSet *bound = [sm respondsToSelector:@selector(boundPointerUIScenes)] ? G4B_Obj(sm, @selector(boundPointerUIScenes)) : nil;
    if (bound) [scenes unionSet:bound];
    id cur = G4B_Ivar(self, "_currentScene");
    if (cur) [scenes addObject:cur];
    if (scenes.count == 0) {
        NSSet *all = [sm respondsToSelector:@selector(allScenes)] ? G4B_Obj(sm, @selector(allScenes)) : nil;
        static BOOL fell;                                           // safety net: one 16.0-style pass if the producer never fired
        if (all.count && !fell) {
            fell = YES;
            BP_Log(@"presubset: empty subset, falling back once");
            %orig;
            return;
        }
        if (completion) completion();
        return;
    }
    BP_Log(@"presubset: updating %lu scenes", (unsigned long)scenes.count);
    __block NSUInteger done = 0;
    NSUInteger total = scenes.count;
    SEL upd = NSSelectorFromString(@"updateSettings:withTransitionContext:completion:");
    CGRect bounds = [cfg respondsToSelector:@selector(bounds)] ? ((CGRect (*)(id, SEL))objc_msgSend)(cfg, @selector(bounds)) : CGRectZero;
    for (id scene in scenes) {
        id settings = [scene respondsToSelector:@selector(settings)] ? G4B_Obj(scene, @selector(settings)) : nil;
        id ms = [settings mutableCopy];
        if (!ms || ![scene respondsToSelector:upd]) { if (++done == total && completion) completion(); continue; }
        if ([ms respondsToSelector:NSSelectorFromString(@"setDisplayConfiguration:")]) ((void (*)(id, SEL, id))objc_msgSend)(ms, NSSelectorFromString(@"setDisplayConfiguration:"), cfg);
        if ([ms respondsToSelector:NSSelectorFromString(@"setFrame:")]) ((void (*)(id, SEL, CGRect))objc_msgSend)(ms, NSSelectorFromString(@"setFrame:"), bounds);
        void (^each)(BOOL) = ^(BOOL ok) { if (++done == total && completion) completion(); };
        ((void (*)(id, SEL, id, id, id))objc_msgSend)(scene, upd, ms, nil, each);
    }
}
%end

%end // G4B_PreSubset

// ----- (item 3 ends)

// ================================================================================================================
// 4. 100 ms DEFERRED ACTIVATION OF EXTERNAL-DISPLAY ASSERTIONS                                           [DONE]
// ================================================================================================================
static BOOL G4B_StackPending(id stack) { return [objc_getAssociatedObject(stack, kG4BKeyA) boolValue]; }

%group G4B_DeferAct

%hook _SBDisplayAssertionStack
// 16.2 -activateAssertionsForDisplay: (0x1c74d1898)
%new
- (void)activateAssertionsForDisplay:(id)display {
    if (!G4B_StackPending(self)) return;                               // 16.2 NSAssert(!_activated)
    objc_setAssociatedObject(self, kG4BKeyA, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    BOOL inval = NO;
    G4B_IvarBytes(self, "_invalidated", &inval, sizeof inval);
    if (inval) return;                                                  // 16.2 NSAssert(!_invalidated)
    id prefs = G4B_Ivar(self, "_assertionControlPreferences");
    Class mt = NSClassFromString(@"NSMapTable");
    SEL ev = @selector(_evalAndApplyOldPreferences:newPreferences:);
    if (prefs && [self respondsToSelector:ev])
        ((void (*)(id, SEL, id, id))objc_msgSend)(self, ev, [mt new], prefs);
}
// the sink: 16.2 only calls it when _activated
- (void)_evalAndApplyOldPreferences:(id)oldPrefs newPreferences:(id)newPrefs {
    if (G4B_StackPending(self)) return;
    %orig;
}
%end

%hook SBDisplayAssertionCoordinator
%new
- (void)activateAssertionsForDisplay:(id)display {                     // 16.2 0x1c77de510
    if (!display || (![display respondsToSelector:@selector(isRootIdentity)] || !G4B_Bool(display, @selector(isRootIdentity)))) return;
    NSDictionary *map = G4B_Ivar(self, "_assertionStackMap");
    id stack = map[display];
    if ([stack respondsToSelector:@selector(activateAssertionsForDisplay:)]) ((void (*)(id, SEL, id))objc_msgSend)(stack, @selector(activateAssertionsForDisplay:), display);
}
- (id)_createDisplayAssertionStackForRootDisplay:(id)display {
    id stack = %orig;
    if (stack && G4B_On("deferact") && [display respondsToSelector:@selector(isExternal)] && G4B_Bool(display, @selector(isExternal))) {
        objc_setAssociatedObject(stack, kG4BKeyA, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);       // _activated = NO
        __weak id wself = self; __weak id wstack = stack;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            id s = wself, st = wstack;
            if (!s || !st) return;
            NSDictionary *map = G4B_Ivar(s, "_assertionStackMap");
            if (map[display] != st) return;                                                       // display gone / replaced
            BOOL inval = NO;
            G4B_IvarBytes(st, "_invalidated", &inval, sizeof inval);
            if (inval) return;                                                                    // [record isValid] == NO
            ((void (*)(id, SEL, id))objc_msgSend)(s, @selector(activateAssertionsForDisplay:), display);
        });
    }
    return stack;
}
%end

%end // G4B_DeferAct

// ----- (item 4 ends)

// ================================================================================================================
// 5. PER-WINDOW-SCENE SBLockedPointerManager, _UIPointerUnlockAction, SUPPRESS-PREFERRED-STATUS            [UNSURE, md 5.6]
// ================================================================================================================
static const void *kLPMScene = &kLPMScene;      // on SBLockedPointerManager: G4BWeakBox -> SBWindowScene
static const void *kLPMHw    = &kLPMHw;         // on SBLockedPointerManager: NSString display hardware id (external scenes only)
static const void *kLPMInv   = &kLPMInv;        // on SBLockedPointerManager: NSNumber BOOL _queue_isInvalidated
static const void *kLPMSup   = &kLPMSup;        // on SBLockedPointerManager: NSMutableSet _queue_sceneIdentifiersThatSuppressPreferredLockStatus (queue only)
static const void *kLPMOwn   = &kLPMOwn;        // on SBWindowScene: the manager
static const void *kLPMSupC  = &kLPMSupC;       // on SBFluidSwitcherItemContainer: NSNumber BOOL

@interface G4BWeakBox : NSObject
@property (nonatomic, weak) id obj;
@end
@implementation G4BWeakBox
@end

static id G4B_LPMScene(id m) { return ((G4BWeakBox *)objc_getAssociatedObject(m, kLPMScene)).obj; }
static BOOL G4B_LPMInv(id m) {                               // snapshot taken with dispatch_sync on the manager's queue, like 16.2
    dispatch_queue_t q = (dispatch_queue_t)G4B_Ivar(m, "_stateSerialQueue");
    __block BOOL inv = NO;
    if (q) dispatch_sync(q, ^{ inv = [objc_getAssociatedObject(m, kLPMInv) boolValue]; });
    else inv = [objc_getAssociatedObject(m, kLPMInv) boolValue];
    return inv;
}
static BOOL G4B_LPMInvOnQueue(id m) { return [objc_getAssociatedObject(m, kLPMInv) boolValue]; }
static void G4B_SetObjIvar(id obj, const char *name, id v) {
    Ivar iv = class_getInstanceVariable(object_getClass(obj), name);
    if (iv) object_setIvar(obj, iv, v);
}
static void G4B_OnLPMQueue(id m, dispatch_block_t b) {
    dispatch_queue_t q = (dispatch_queue_t)G4B_Ivar(m, "_stateSerialQueue");
    if (q) dispatch_async(q, b);
}
static id G4B_GlobalLockedPointerManager(void) {
    return G4B_Ivar([UIApplication sharedApplication], "_lockedPointerManager");
}
static void G4B_LPMAttach(id m, id ws, BOOL external) {
    G4BWeakBox *box = [G4BWeakBox new];
    box.obj = ws;
    objc_setAssociatedObject(m, kLPMScene, box, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (external) {
        id cfg = [ws respondsToSelector:@selector(_fbsDisplayConfiguration)] ? G4B_Obj(ws, @selector(_fbsDisplayConfiguration)) : nil;
        NSString *hw = [cfg respondsToSelector:@selector(hardwareIdentifier)] ? G4B_Obj(cfg, @selector(hardwareIdentifier)) : nil;
        if (hw.length) objc_setAssociatedObject(m, kLPMHw, hw, OBJC_ASSOCIATION_RETAIN_NONATOMIC);   // captured on the main thread (review F4)
    }
}

%group G4B_LockedPtr

%hook SBWindowScene
%new
- (id)lockedPointerManager {
    id m = objc_getAssociatedObject(self, kLPMOwn);
    if (m) return m;
    id wsm = [[UIApplication sharedApplication] respondsToSelector:@selector(windowSceneManager)] ? G4B_Obj([UIApplication sharedApplication], @selector(windowSceneManager)) : nil;
    id emb = [wsm respondsToSelector:@selector(embeddedDisplayWindowScene)] ? G4B_Obj(wsm, @selector(embeddedDisplayWindowScene)) : nil;
    if (emb == self) {
        m = G4B_GlobalLockedPointerManager();                       // 16.0: the one global manager serves the iPad scene
        if (!m) return nil;
        G4B_LPMAttach(m, self, NO);
    } else {
        Class k = NSClassFromString(@"SBLockedPointerManager");
        id sm = [self respondsToSelector:@selector(sceneManager)] ? G4B_Obj(self, @selector(sceneManager)) : nil;
        if (!k || !sm || ![k instancesRespondToSelector:@selector(initWithSceneManager:)]) return nil;
        m = ((id (*)(id, SEL, id))objc_msgSend)([k alloc], @selector(initWithSceneManager:), sm);
        if (!m) return nil;
        G4B_LPMAttach(m, self, YES);
        BP_Log(@"lockedptr2: created manager for external scene");
    }
    objc_setAssociatedObject(self, kLPMOwn, m, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return m;
}
%end

%hook SBLockedPointerManager
%new
- (id)initWithWindowScene:(id)ws {
    id sm = [ws respondsToSelector:@selector(sceneManager)] ? G4B_Obj(ws, @selector(sceneManager)) : nil;
    id m = ((id (*)(id, SEL, id))objc_msgSend)(self, @selector(initWithSceneManager:), sm);
    if (m) G4B_LPMAttach(m, ws, NO);
    return m;
}
// 16.2 -invalidate (0x1c76b9298)
%new
- (void)invalidate {
    id ws = G4B_LPMScene(self);
    id sm = [ws respondsToSelector:@selector(sceneManager)] ? G4B_Obj(ws, @selector(sceneManager)) : nil;
    if ([sm respondsToSelector:@selector(removeObserver:)]) ((void (*)(id, SEL, id))objc_msgSend)(sm, @selector(removeObserver:), self);
    id coord = [sm respondsToSelector:@selector(_layoutStateTransitionCoordinator)] ? G4B_Obj(sm, @selector(_layoutStateTransitionCoordinator)) : nil;
    if ([coord respondsToSelector:@selector(removeObserver:)]) ((void (*)(id, SEL, id))objc_msgSend)(coord, @selector(removeObserver:), self);
    dispatch_queue_t q = (dispatch_queue_t)G4B_Ivar(self, "_stateSerialQueue");
    __weak id wself = self;
    void (^body)(void) = ^{
        id s = wself; if (!s) return;
        id a = G4B_Ivar(s, "_queue_backboardLockedPointerAssertion"); G4B_SetObjIvar(s, "_queue_backboardLockedPointerAssertion", nil);
        if ([a respondsToSelector:@selector(invalidate)]) [(id<G4BInvalidatable>)a invalidate];
        id h = G4B_Ivar(s, "_queue_pointerHiddenAssertion"); G4B_SetObjIvar(s, "_queue_pointerHiddenAssertion", nil);
        if ([h respondsToSelector:@selector(invalidate)]) [(id<G4BInvalidatable>)h invalidate];
        objc_setAssociatedObject(s, kLPMInv, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    };
    if (q) dispatch_sync(q, body); else body();
}
// 16.2 clientWithSceneIdentifier:suppressPreferredLockStatus: (0x1c76b8fc4)
%new
- (void)clientWithSceneIdentifier:(NSString *)sid suppressPreferredLockStatus:(BOOL)suppress {
    dispatch_queue_t q = (dispatch_queue_t)G4B_Ivar(self, "_stateSerialQueue");
    if (!q || !sid) return;
    __block BOOL inv = NO;
    dispatch_sync(q, ^{
        inv = G4B_LPMInvOnQueue(self);
        if (inv) return;
        NSMutableSet *set = objc_getAssociatedObject(self, kLPMSup);
        if (!set) { set = [NSMutableSet set]; objc_setAssociatedObject(self, kLPMSup, set, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
        BOOL has = [set containsObject:sid];
        if (suppress && !has) [set addObject:sid]; else if (!suppress && has) [set removeObject:sid];
    });
    if (inv) { BP_Log(@"lockedptr2: ignoring suppress request, invalidated"); return; }
    id ws = G4B_LPMScene(self);
    id sw = [ws respondsToSelector:@selector(switcherController)] ? G4B_Obj(ws, @selector(switcherController)) : nil;
    id vc = [sw respondsToSelector:@selector(contentViewController)] ? G4B_Obj(sw, @selector(contentViewController)) : nil;
    Class fl = NSClassFromString(@"SBFluidSwitcherViewController");
    if (vc && fl && [vc isKindOfClass:fl] && [vc respondsToSelector:@selector(clientWithSceneIdentifier:suppressPreferredPointerLockStatusUpdated:)])
        ((void (*)(id, SEL, id, BOOL))objc_msgSend)(vc, @selector(clientWithSceneIdentifier:suppressPreferredPointerLockStatusUpdated:), sid, suppress);
    [self _notInvalidated_updateLockForLayoutState:nil];
}
// 16.2 sceneHandle:didDestroyScene: (0x1c76b9b80)
%new
- (void)sceneHandle:(id)handle didDestroyScene:(id)scene {
    NSString *sid = [scene respondsToSelector:@selector(identifier)] ? G4B_Obj(scene, @selector(identifier)) : nil;
    if (!sid || G4B_LPMInv(self)) return;
    __weak id wself = self;
    G4B_OnLPMQueue(self, ^{
        id s = wself; if (!s) return;
        NSMutableDictionary *prefs = G4B_Ivar(s, "_queue_preferredLockStatusBySceneIdentifier");
        [prefs removeObjectForKey:sid];
        [(NSMutableSet *)objc_getAssociatedObject(s, kLPMSup) removeObject:sid];
    });
    [self _notInvalidated_updateLockForLayoutState:nil];
}
%new
- (void)_notInvalidated_updateLockForLayoutState:(id)state { [self _updateLockForLayoutState:state]; }

// ----- invalid guards (every 16.2 entry point snapshots _queue_isInvalidated)
- (void)clientWithSceneIdentifier:(id)sid prefersPointerLockStatus:(long long)status {
    if (G4B_On("lockedptr2") && G4B_LPMInv(self)) return;
    %orig;
}
- (void)_updateLockForLayoutState:(id)state {
    if (G4B_On("lockedptr2")) {
        if (G4B_LPMInv(self)) return;
        if (!state) {                                               // 16.0 defaults to the MAIN display layout state
            id ws = G4B_LPMScene(self);
            id sm = [ws respondsToSelector:@selector(sceneManager)] ? G4B_Obj(ws, @selector(sceneManager)) : nil;
            id own = [sm respondsToSelector:@selector(currentLayoutState)] ? G4B_Obj(sm, @selector(currentLayoutState)) : nil;
            if (own) {
                %orig(own);
                return;
            }
        }
    }
    %orig;
}
- (void)layoutStateTransitionCoordinator:(id)c transitionDidBeginWithTransitionContext:(id)ctx {
    if (G4B_On("lockedptr2") && G4B_LPMInv(self)) return;
    %orig;
}
- (void)layoutStateTransitionCoordinator:(id)c transitionDidEndWithTransitionContext:(id)ctx {
    if (G4B_On("lockedptr2") && G4B_LPMInv(self)) return;
    %orig;
}
- (void)sceneManager:(id)m didAddExternalForegroundApplicationSceneHandle:(id)h {
    if (G4B_On("lockedptr2") && G4B_LPMInv(self)) return;
    %orig;
}
- (void)sceneManager:(id)m didRemoveExternalForegroundApplicationSceneHandle:(id)h {
    if (G4B_On("lockedptr2") && G4B_LPMInv(self)) return;
    %orig;
}
- (void)sceneHandle:(id)h didUpdateSettingsWithDiff:(id)diff previousSettings:(id)prev {
    if (G4B_On("lockedptr2") && G4B_LPMInv(self)) return;
    %orig;
}

// ----- 16.2 _queue_updateLockForLayoutState: (0x1c76ba124), whole method
- (void)_queue_updateLockForLayoutState:(id)state {
    if (!G4B_On("lockedptr2") || !G4B_LPMScene(self)) {
        %orig;
        return;
    }
    if (G4B_LPMInvOnQueue(self)) { BP_Log(@"lockedptr2: ignoring update, invalidated"); return; }
    id h = [self _possibleSceneHandleForLockingPointerFromLayoutState:state];
    NSString *sid = [h respondsToSelector:@selector(sceneIdentifier)] ? G4B_Obj(h, @selector(sceneIdentifier)) : nil;
    NSString *cur = G4B_Ivar(self, "_queue_sceneIdentifierThatHasLockedPointer");
    BOOL shouldLock = NO;
    if (sid && [self _queue_prefersLockForSceneIdentifier:sid] && ![(NSSet *)objc_getAssociatedObject(self, kLPMSup) containsObject:sid])
        shouldLock = [self _shouldAllowPointerLockedForScene:h];
    BP_Log(@"lockedptr2: scene %@ shouldBeLocked:%d isCurrentlyLocked:%d", sid, shouldLock, cur != nil);
    if (shouldLock && !cur) [self _queue_lockPointerForSceneIdentifier:sid];
    else if (!shouldLock && cur) [self _queue_unlockPointer];
}
// ----- 16.2 _queue_lockPointerForSceneIdentifier: (0x1c76ba3dc), whole method; display scoping decided in md 5.2
- (void)_queue_lockPointerForSceneIdentifier:(NSString *)sid {
    if (!G4B_On("lockedptr2") || !G4B_LPMScene(self) || !sid) {
        %orig;
        return;
    }
    NSString *cur = G4B_Ivar(self, "_queue_sceneIdentifierThatHasLockedPointer");
    if (cur) [self _setPointerLockStatus:0 forSceneWithIdentifier:cur];
    NSString *reason = [NSString stringWithFormat:@"Scene %@ requested locked pointer", sid];
    Class bk = NSClassFromString(@"BKSMousePointerService");
    id svc = [(id)bk respondsToSelector:@selector(sharedInstance)] ? G4B_Obj((id)bk, @selector(sharedInstance)) : nil;
    NSString *display = objc_getAssociatedObject(self, kLPMHw);       // nil for the iPad (identical to 16.0), hardware id for external scenes
    SEL sup = NSSelectorFromString(@"pointerSuppressionAssertionOnDisplay:forReason:withOptionsMask:");
    id a1 = [svc respondsToSelector:sup] ? ((id (*)(id, SEL, id, id, unsigned long long))objc_msgSend)(svc, sup, display, reason, 2) : nil;
    G4B_SetObjIvar(self, "_queue_backboardLockedPointerAssertion", a1);
    id pc = G4B_Ivar(self, "_pointerClientController");
    SEL hide = NSSelectorFromString(@"persistentlyHidePointerAssertionForReason:");
    id a2 = [pc respondsToSelector:hide] ? ((id (*)(id, SEL, unsigned long long))objc_msgSend)(pc, hide, 4) : nil;
    G4B_SetObjIvar(self, "_queue_pointerHiddenAssertion", a2);
    G4B_SetObjIvar(self, "_queue_sceneIdentifierThatHasLockedPointer", sid);
    [self _setPointerLockStatus:1 forSceneWithIdentifier:sid];
    BP_Log(@"lockedptr2: locked pointer for %@ on display %@", sid, display ?: @"<main>");
}
// ----- 16.2 _shouldAllowPointerLockedForScene: (0x1c76b9e5c): Control Center only counts for ITS OWN window scene
- (BOOL)_shouldAllowPointerLockedForScene:(id)handle {
    id ws = G4B_LPMScene(self);
    if (!G4B_On("lockedptr2") || !ws) return %orig;
    Class ccc = NSClassFromString(@"SBControlCenterController"), cvc = NSClassFromString(@"SBCoverSheetPresentationManager");
    id cc = [(id)ccc respondsToSelector:@selector(sharedInstance)] ? G4B_Obj((id)ccc, @selector(sharedInstance)) : nil;
    id win = [cc respondsToSelector:@selector(_controlCenterWindow)] ? G4B_Obj(cc, @selector(_controlCenterWindow)) : nil;
    id ccws = [win respondsToSelector:@selector(windowScene)] ? G4B_Obj(win, @selector(windowScene)) : nil;
    BOOL ccOK = (ccws && [ccws isEqual:ws]) ? !G4B_Bool(cc, @selector(isPresented)) : YES;
    id cov = [(id)cvc respondsToSelector:@selector(sharedInstance)] ? G4B_Obj((id)cvc, @selector(sharedInstance)) : nil;
    BOOL coverOK = ![cov respondsToSelector:@selector(isPresented)] || !G4B_Bool(cov, @selector(isPresented));
    id scene = [handle respondsToSelector:@selector(sceneIfExists)] ? G4B_Obj(handle, @selector(sceneIfExists)) : nil;
    BOOL sceneOK = NO;
    if (scene) {
        BOOL fg = [handle respondsToSelector:@selector(isEffectivelyForeground)] && G4B_Bool(handle, @selector(isEffectivelyForeground));
        id settings = [scene respondsToSelector:@selector(settings)] ? G4B_Obj(scene, @selector(settings)) : nil;
        BOOL ui = [settings respondsToSelector:@selector(isUISubclass)] && G4B_Bool(settings, @selector(isUISubclass));
        unsigned long long reasons = [settings respondsToSelector:@selector(deactivationReasons)] ? (unsigned long long)G4B_LL(settings, @selector(deactivationReasons)) : 0;
        sceneOK = fg && (!ui || (reasons & ~0x100ull) == 0);
    }
    BP_Log(@"lockedptr2: shouldAllow:%d cc:%d cover:%d scene:%d", ccOK && coverOK && sceneOK, ccOK, coverOK, sceneOK);
    return ccOK && coverOK && sceneOK;
}
%end

// ----- external display apps can lock the pointer: forward the client-settings change (16.2 inspector block 0x1c7859008)
%hook SBSystemShellExternalDisplaySceneManager
- (void)_scene:(id)scene didUpdateClientSettingsWithDiff:(id)diff oldClientSettings:(id)old transitionContext:(id)ctx {
    %orig;
    if (!G4B_On("lockedptr2") || !scene) return;
    id cs = [scene respondsToSelector:@selector(clientSettings)] ? G4B_Obj(scene, @selector(clientSettings)) : nil;
    SEL ps = NSSelectorFromString(@"preferredPointerLockStatus");
    if (![cs respondsToSelector:ps]) return;
    long long st = G4B_LL(cs, ps);
    long long ost = [old respondsToSelector:ps] ? G4B_LL(old, ps) : 0;
    if (st == ost) return;
    id ws = [self respondsToSelector:@selector(windowScene)] ? G4B_Obj(self, @selector(windowScene)) : nil;
    id m = [ws respondsToSelector:@selector(lockedPointerManager)] ? G4B_Obj(ws, @selector(lockedPointerManager)) : nil;
    NSString *sid = [scene respondsToSelector:@selector(identifier)] ? G4B_Obj(scene, @selector(identifier)) : nil;
    if (m && sid) {
        BP_Log(@"lockedptr2: client prefers %lld for %@", st, sid);
        ((void (*)(id, SEL, id, long long))objc_msgSend)(m, @selector(clientWithSceneIdentifier:prefersPointerLockStatus:), sid, st);
    }
}
%end

// ----- _UIPointerUnlockAction (16.2 0x1c72e3f38)
%hook SBSceneManager
- (BOOL)_handleAction:(id)action forScene:(id)scene {
    Class pu = NSClassFromString(@"_UIPointerUnlockAction");
    if (G4B_On("lockedptr2") && pu && [action isKindOfClass:pu]) {
        id ws = [self respondsToSelector:@selector(_windowScene)] ? G4B_Obj(self, @selector(_windowScene)) : nil;
        id m = [ws respondsToSelector:@selector(lockedPointerManager)] ? G4B_Obj(ws, @selector(lockedPointerManager)) : nil;
        NSString *sid = [scene respondsToSelector:@selector(identifier)] ? G4B_Obj(scene, @selector(identifier)) : nil;
        if (m && sid) {
            ((void (*)(id, SEL, id, BOOL))objc_msgSend)(m, @selector(clientWithSceneIdentifier:suppressPreferredLockStatus:), sid, YES);
            return YES;
        }
    }
    return %orig;
}
%end

// ----- teardown (16.2 SBAbstractWindowSceneDelegate sceneDidDisconnect:)
%hook SBAbstractWindowSceneDelegate
- (void)sceneDidDisconnect:(id)scene {
    if (G4B_On("lockedptr2")) {
        id m = objc_getAssociatedObject(scene, kLPMOwn);
        if (m && m != G4B_GlobalLockedPointerManager() && [m respondsToSelector:@selector(invalidate)]) [(id<G4BInvalidatable>)m invalidate];
    }
    %orig;
}
%end

// ----- switcher side
%hook SBFluidSwitcherViewController
%new
- (void)clientWithSceneIdentifier:(NSString *)sid suppressPreferredPointerLockStatusUpdated:(BOOL)suppress {     // 0x1c7451f0c
    id overlay = [self respondsToSelector:@selector(liveOverlayForSceneIdentifier:)] ? G4B_Obj1(self, @selector(liveOverlayForSceneIdentifier:), sid) : nil;
    NSDictionary *live = G4B_Ivar(self, "_liveContentOverlays");
    if (!overlay || ![live isKindOfClass:[NSDictionary class]]) return;
    for (id appLayout in [live allKeysForObject:overlay]) {
        id c = [self respondsToSelector:@selector(_itemContainerForAppLayoutIfExists:)] ? G4B_Obj1(self, @selector(_itemContainerForAppLayoutIfExists:), appLayout) : nil;
        if ([c respondsToSelector:@selector(setPreferredPointerLockStatusSuppressed:)]) ((void (*)(id, SEL, BOOL))objc_msgSend)(c, @selector(setPreferredPointerLockStatusSuppressed:), suppress);
    }
}
- (void)didSelectContainer:(id)container modifierFlags:(long long)flags {
    if (G4B_On("lockedptr2") && [container respondsToSelector:@selector(appLayout)]) {
        id layout = G4B_Obj(container, @selector(appLayout));
        id item = [layout respondsToSelector:@selector(itemForLayoutRole:)] ? ((id (*)(id, SEL, long long))objc_msgSend)(layout, @selector(itemForLayoutRole:), 1) : nil;
        NSString *uid = [item respondsToSelector:@selector(uniqueIdentifier)] ? G4B_Obj(item, @selector(uniqueIdentifier)) : nil;
        id sw = G4B_Ivar(self, "_switcherController");
        id ws = [sw respondsToSelector:@selector(windowScene)] ? G4B_Obj(sw, @selector(windowScene)) : nil;
        id m = [ws respondsToSelector:@selector(lockedPointerManager)] ? G4B_Obj(ws, @selector(lockedPointerManager)) : nil;
        if (uid && m) ((void (*)(id, SEL, id, BOOL))objc_msgSend)(m, @selector(clientWithSceneIdentifier:suppressPreferredLockStatus:), uid, NO);
    }
    %orig;
}
%end

%hook SBFluidSwitcherItemContainer
%new
- (BOOL)isPreferredPointerLockStatusSuppressed { return [objc_getAssociatedObject(self, kLPMSupC) boolValue]; }
%new
- (void)setPreferredPointerLockStatusSuppressed:(BOOL)suppressed {                                              // 0x1c75e161c
    if ([self isPreferredPointerLockStatusSuppressed] == suppressed) return;
    objc_setAssociatedObject(self, kLPMSupC, suppressed ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self setContentViewBlocksTouches:[self contentViewBlocksTouches]];
    [self setSelectable:[self isSelectable]];
}
- (void)setContentViewBlocksTouches:(BOOL)blocks {                                                               // 0x1c75e15c8
    %orig(blocks || [self isPreferredPointerLockStatusSuppressed]);
}
- (void)setSelectable:(BOOL)selectable {                                                                         // 0x1c75e15f4
    %orig(selectable || [self isPreferredPointerLockStatusSuppressed]);
}
%end

%end // G4B_LockedPtr

// ----- (item 5 ends)

// ================================================================================================================
// 6a. WINDOWS MIGRATE TO THE iPAD ON UNPLUG                                                            [DONE]
// ================================================================================================================
%group G4B_Migrate

%hook SBMainSwitcherControllerCoordinator
- (void)windowSceneDidDisconnect:(id)scene {
    Class wsc = NSClassFromString(@"SBWindowScene");
    if (G4B_On("migrate") && wsc && [scene isKindOfClass:wsc] && [scene respondsToSelector:@selector(isExternalDisplayWindowScene)] && G4B_Bool(scene, @selector(isExternalDisplayWindowScene))) {
        id ident = [scene respondsToSelector:@selector(_fbsDisplayIdentity)] ? G4B_Obj(scene, @selector(_fbsDisplayIdentity)) : nil;
        SEL wm = NSSelectorFromString(@"sb_displayWindowingMode");
        long long mode = [ident respondsToSelector:wm] ? G4B_LL(ident, wm) : 0;
        if (mode == 1) {
            id wsm = [[UIApplication sharedApplication] respondsToSelector:@selector(windowSceneManager)] ? G4B_Obj([UIApplication sharedApplication], @selector(windowSceneManager)) : nil;
            id emb = [wsm respondsToSelector:@selector(embeddedDisplayWindowScene)] ? G4B_Obj(wsm, @selector(embeddedDisplayWindowScene)) : nil;
            id embSM = [emb respondsToSelector:@selector(sceneManager)] ? G4B_Obj(emb, @selector(sceneManager)) : nil;
            Class mdc = NSClassFromString(@"SBMainDisplaySceneManager");
            id switcher = [self respondsToSelector:@selector(switcherControllerForWindowScene:)] ? G4B_Obj1(self, @selector(switcherControllerForWindowScene:), scene) : nil;
            SEL take = NSSelectorFromString(@"takeScene:fromSceneManager:");
            if (switcher && embSM && mdc && [embSM isKindOfClass:mdc] && [embSM respondsToSelector:take] && [self respondsToSelector:@selector(appLayoutsForSwitcherController:)]) {
                BOOL moved = NO;
                NSUInteger n = 0;
                id srcSM = [scene respondsToSelector:@selector(sceneManager)] ? G4B_Obj(scene, @selector(sceneManager)) : nil;
                for (id layout in (id<NSFastEnumeration>)G4B_Obj1(self, @selector(appLayoutsForSwitcherController:), switcher)) {
                    id items = [layout respondsToSelector:@selector(allItems)] ? G4B_Obj(layout, @selector(allItems)) : nil;
                    for (id item in (id<NSFastEnumeration>)items) {
                        SEL hs = @selector(_deviceApplicationSceneHandleForDisplayItem:);
                        id h = [self respondsToSelector:hs] ? G4B_Obj1(self, hs, item) : nil;
                        id sc = [h respondsToSelector:@selector(sceneIfExists)] ? G4B_Obj(h, @selector(sceneIfExists)) : nil;
                        if (!sc || !srcSM) continue;
                        ((void (*)(id, SEL, id, id))objc_msgSend)(embSM, take, sc, srcSM);
                        moved = YES; n++;
                    }
                }
                BP_Log(@"migrate: moved %lu scenes to the embedded scene manager", (unsigned long)n);
                if (moved) {
                    Class mw = NSClassFromString(@"SBMainWorkspace");
                    id ws2 = [(id)mw respondsToSelector:@selector(mainWorkspace)] ? G4B_Obj((id)mw, @selector(mainWorkspace)) : nil;
                    SEL rq = NSSelectorFromString(@"requestTransitionWithOptions:builder:validator:");
                    if ([ws2 respondsToSelector:rq]) {
                        __weak id wEmb = embSM;
                        void (^builder)(id) = ^(id request) {
                            SEL mac = NSSelectorFromString(@"modifyApplicationContext:");
                            if (![request respondsToSelector:mac]) return;
                            void (^mod)(id) = ^(id ctx) {
                                id ls = [wEmb respondsToSelector:@selector(currentLayoutState)] ? G4B_Obj(wEmb, @selector(currentLayoutState)) : nil;
                                SEL wpr = NSSelectorFromString(@"windowPickerRole"), uem = NSSelectorFromString(@"unlockedEnvironmentMode");
                                long long role = [ls respondsToSelector:wpr] ? G4B_LL(ls, wpr) : 0;
                                typedef BOOL (*ValidFn)(long long);
                                ValidFn valid = (ValidFn)dlsym(RTLD_DEFAULT, "SBLayoutRoleIsValid");
                                if (role && (!valid || valid(role)) && [ctx respondsToSelector:NSSelectorFromString(@"setRequestedWindowPickerRole:")])
                                    ((void (*)(id, SEL, long long))objc_msgSend)(ctx, NSSelectorFromString(@"setRequestedWindowPickerRole:"), role);
                                if ([ls respondsToSelector:uem] && G4B_LL(ls, uem) == 2 && [ctx respondsToSelector:NSSelectorFromString(@"setRequestedUnlockedEnvironmentMode:")])
                                    ((void (*)(id, SEL, long long))objc_msgSend)(ctx, NSSelectorFromString(@"setRequestedUnlockedEnvironmentMode:"), 2);
                            };
                            ((void (*)(id, SEL, id))objc_msgSend)(request, mac, mod);
                        };
                        ((BOOL (*)(id, SEL, unsigned long long, id, id))objc_msgSend)(ws2, rq, 0, builder, nil);
                    }
                }
            }
        }
    }
    %orig;
}
%end

%hook SBSceneManager
// 16.2 adds [oldHandle _noteReplacedWithSceneHandle:newHandle] after the move (0x1c73e9ba8)
- (void)takeScene:(id)scene fromSceneManager:(id)other {
    SEL ex = NSSelectorFromString(@"existingSceneHandleForScene:"), note = NSSelectorFromString(@"_noteReplacedWithSceneHandle:");
    id oldH = ([self respondsToSelector:ex] && scene && G4B_On("migrate")) ? G4B_Obj1(other ?: self, ex, scene) : nil;
    %orig;
    if (!oldH || ![oldH respondsToSelector:note]) return;
    id newH = G4B_Obj1(self, ex, scene);
    if (newH && newH != oldH) ((void (*)(id, SEL, id))objc_msgSend)(oldH, note, newH);
}
%end

%end // G4B_Migrate

// ================================================================================================================
// 6b. PER-DISPLAY KEYBOARD-FOCUS LOCK REASONS                                                            [DONE, UNSURE md 6b]
// ================================================================================================================
@interface G4BFocusReq : NSObject {
@public
    NSString *reason;
    __weak id scene;          // SBWindowScene (lock) or the window's scene (steal)
    __weak id window;
    BOOL steal;
    id real;                  // the real 16.0 BSInvalidatable while the request qualifies
    BOOL dead;
}
@end
@implementation G4BFocusReq
@end

@interface G4BFocusToken : NSObject <G4BInvalidatable>
- (instancetype)initWithKFC:(id)kfc request:(G4BFocusReq *)r;
@end

static BOOL gG4BInReconcile;
static const void *kFocusList = &kFocusList;
static const void *kFocusObs  = &kFocusObs;

@interface G4BFocusObserver : NSObject
@property (nonatomic, weak) id kfc;
@end

static id G4B_WindowSceneManager(void) {
    return [[UIApplication sharedApplication] respondsToSelector:@selector(windowSceneManager)] ? G4B_Obj([UIApplication sharedApplication], @selector(windowSceneManager)) : nil;
}
static id G4B_SceneDisplayWindowScene(id fbScene) {
    id settings = [fbScene respondsToSelector:@selector(settings)] ? G4B_Obj(fbScene, @selector(settings)) : nil;
    SEL ds = NSSelectorFromString(@"sb_displayIdentityForSceneManagers");
    id ident = [settings respondsToSelector:ds] ? G4B_Obj(settings, ds) : nil;
    id wsm = G4B_WindowSceneManager();
    return (ident && [wsm respondsToSelector:@selector(windowSceneForDisplayIdentity:)]) ? G4B_Obj1(wsm, @selector(windowSceneForDisplayIdentity:), ident) : nil;
}
static void G4B_FocusReconcile(id kfc);

@implementation G4BFocusToken {
    __weak id _kfc;
    G4BFocusReq *_req;
}
- (instancetype)initWithKFC:(id)kfc request:(G4BFocusReq *)r {
    if ((self = [super init])) { _kfc = kfc; _req = r; }
    return self;
}
- (void)invalidate {
    G4BFocusReq *r = _req; _req = nil;
    if (!r || r->dead) return;
    r->dead = YES;
    id real = r->real; r->real = nil;
    if ([real respondsToSelector:@selector(invalidate)]) [(id<G4BInvalidatable>)real invalidate];
    id kfc = _kfc;
    NSMutableArray *list = objc_getAssociatedObject(kfc, kFocusList);
    [list removeObject:r];
    if (kfc) G4B_FocusReconcile(kfc);
}
- (void)dealloc { [self invalidate]; }
@end

@implementation G4BFocusObserver
- (void)keyboardFocusController:(id)c externalSceneDidAcquireFocus:(id)f { id k = self.kfc; if (k) G4B_FocusReconcile(k); }
- (void)keyboardFocusController:(id)c didUpdateWindowSceneWithFocusFrom:(id)from to:(id)to { id k = self.kfc; if (k) G4B_FocusReconcile(k); }
- (void)multiDisplayUserInteractionCoordinator:(id)c updatedActiveWindowScene:(id)ws { id k = self.kfc; if (k) G4B_FocusReconcile(k); }
@end

static void G4B_FocusReconcileNow(id kfc) {
    NSMutableArray<G4BFocusReq *> *list = objc_getAssociatedObject(kfc, kFocusList);
    if (!list.count || gG4BInReconcile) return;
    id wsm = G4B_WindowSceneManager();
    id appScene = G4B_SceneDisplayWindowScene(G4B_Ivar(kfc, "_externalSceneWithFocus"));
    SEL fu = NSSelectorFromString(@"activeDisplayWindowSceneFollowingUserInteraction");
    id active = [wsm respondsToSelector:fu] ? G4B_Obj(wsm, fu) : ([wsm respondsToSelector:@selector(activeDisplayWindowScene)] ? G4B_Obj(wsm, @selector(activeDisplayWindowScene)) : nil);
    gG4BInReconcile = YES;
    for (G4BFocusReq *r in [list copy]) {
        if (r->dead) continue;
        id sc = r->scene;
        BOOL want = (!appScene && !active) || (sc && (sc == appScene || sc == active));
        if (want && !r->real) {
            id real = nil;
            if (r->steal) {
                real = ((id (*)(id, SEL, id, id))objc_msgSend)(kfc, @selector(requestFocusStealingForSpringBoardWindow:forReason:), r->window, r->reason);
            } else {
                real = ((id (*)(id, SEL, id, id))objc_msgSend)(kfc, @selector(lockFocusToSpringBoardWindowScene:forReason:), sc, r->reason);
            }
            r->real = real;
            BP_Log(@"focuslock: activating %@ (%@)", r->reason, r->steal ? @"steal" : @"lock");
        } else if (!want && r->real) {
            id real = r->real; r->real = nil;
            if ([real respondsToSelector:@selector(invalidate)]) [(id<G4BInvalidatable>)real invalidate];
            BP_Log(@"focuslock: deferring %@ (scene not on app-focus/active display)", r->reason);
        }
    }
    gG4BInReconcile = NO;
}
static void G4B_FocusReconcile(id kfc) {
    __weak id w = kfc;
    dispatch_async(dispatch_get_main_queue(), ^{ id k = w; if (k) G4B_FocusReconcileNow(k); });
}

%group G4B_FocusLock

%hook SBWorkspaceKeyboardFocusController
- (id)lockFocusToSpringBoardWindowScene:(id)scene forReason:(id)reason {
    if (gG4BInReconcile || !G4B_On("focuslock") || !scene || ![reason isKindOfClass:[NSString class]]) return %orig;
    G4BFocusReq *r = [G4BFocusReq new];
    r->reason = reason; r->scene = scene;
    NSMutableArray *list = objc_getAssociatedObject(self, kFocusList);
    if (!list) { list = [NSMutableArray array]; objc_setAssociatedObject(self, kFocusList, list, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    [list addObject:r];
    G4B_FocusReconcileNow(self);
    return [[G4BFocusToken alloc] initWithKFC:self request:r];
}
- (id)requestFocusStealingForSpringBoardWindow:(id)window forReason:(id)reason {
    if (gG4BInReconcile || !G4B_On("focuslock") || !window || ![reason isKindOfClass:[NSString class]]) return %orig;
    G4BFocusReq *r = [G4BFocusReq new];
    r->reason = reason; r->window = window; r->steal = YES;
    r->scene = [window respondsToSelector:@selector(_sbWindowScene)] ? G4B_Obj(window, @selector(_sbWindowScene)) : nil;
    NSMutableArray *list = objc_getAssociatedObject(self, kFocusList);
    if (!list) { list = [NSMutableArray array]; objc_setAssociatedObject(self, kFocusList, list, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    [list addObject:r];
    G4B_FocusReconcileNow(self);
    return [[G4BFocusToken alloc] initWithKFC:self request:r];
}
- (void)updateKeyboardFocusDeferringRules {
    %orig;
    if (G4B_On("focuslock")) G4B_FocusReconcile(self);
}
- (void)removeKeyboardFocusFromScene:(id)scene {
    %orig;
    if (G4B_On("focuslock")) G4B_FocusReconcile(self);
}
- (void)windowSceneDidConnect:(id)ws {
    %orig;
    if (!G4B_On("focuslock") || objc_getAssociatedObject(self, kFocusObs)) return;
    G4BFocusObserver *o = [G4BFocusObserver new];
    o.kfc = self;
    if ([self respondsToSelector:@selector(addKeyboardFocusObserver:)]) {
        id tok = G4B_Obj1(self, @selector(addKeyboardFocusObserver:), o);
        objc_setAssociatedObject(self, kFocusObs, @[o, tok ?: [NSNull null]], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    id sb = [UIApplication sharedApplication];
    SEL mc = NSSelectorFromString(@"multiDisplayUserInteractionCoordinator");     // provided by Group4Focus.x
    id coord = [sb respondsToSelector:mc] ? G4B_Obj(sb, mc) : nil;
    if ([coord respondsToSelector:@selector(addActiveDisplayWindowSceneObserver:)]) ((void (*)(id, SEL, id))objc_msgSend)(coord, @selector(addActiveDisplayWindowSceneObserver:), o);
}
%end

%end // G4B_FocusLock

// ----- (item 6 ends)

// ================================================================================================================
// 7. ACTIVE-DISPLAY TRACKING METHODOLOGY, DISPLAY ARRANGEMENT ITEM                                       [DONE]
// ================================================================================================================
static NSString *const kG4BMethodologyChanged = @"BP162ActiveDisplayTrackingMethodologyChanged";
static const void *kMethKey = &kMethKey;

static long long G4B_Methodology(void) {
    if (G4B_OptIn("methodology0")) return 0;                       // <jbroot>/tmp/Backport162.on.methodology0 : keyboard following (16.0 behaviour)
    Class dom = NSClassFromString(@"SBExternalDisplaySettingsDomain");
    id root = [(id)dom respondsToSelector:@selector(rootSettings)] ? G4B_Obj((id)dom, @selector(rootSettings)) : nil;
    return [root respondsToSelector:@selector(activeDisplayTrackingMethodology)] ? G4B_LL(root, @selector(activeDisplayTrackingMethodology)) : 1;
}
// 16.2 _SBStringForActiveDisplayTrackingMethodology (0x1c74241b8)
static NSString *G4B_StringForMethodology(long long m) { return m == 0 ? @"keyboard" : (m == 1 ? @"touch + pointer" : [NSString stringWithFormat:@"<unknown:%lld>", m]); }

%group G4B_Arrange

%hook SBExternalDisplaySettings
%new
- (long long)activeDisplayTrackingMethodology {
    NSNumber *n = objc_getAssociatedObject(self, kMethKey);
    return n ? n.longLongValue : 1;
}
%new
- (void)setActiveDisplayTrackingMethodology:(long long)m {
    objc_setAssociatedObject(self, kMethKey, @(m), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [[NSNotificationCenter defaultCenter] postNotificationName:kG4BMethodologyChanged object:self];
}
- (void)setDefaultValues {
    %orig;
    [self setActiveDisplayTrackingMethodology:1];                    // 16.2 0x1c742368c
}
%end

%hook SBWindowSceneManager
- (id)activeDisplayWindowScene {                                     // 16.2 0x1c74bf1c4
    SEL kb = NSSelectorFromString(@"activeDisplayWindowSceneFollowingKeyboard"), ui = NSSelectorFromString(@"activeDisplayWindowSceneFollowingUserInteraction");
    if (G4B_On("arrange") && [self respondsToSelector:kb] && [self respondsToSelector:ui]) {
        long long m = G4B_Methodology();
        id r = nil;
        if (m == 0) r = G4B_Obj(self, kb);
        else if (m == 1) r = G4B_Obj(self, ui);
        else BP_Log(@"arrange: undefined methodology %@", G4B_StringForMethodology(m));
        // stock 16.0 never returns nil (about 60 callers rely on it): the following-user-interaction scene is nil until the first touch
        if (r) return r;
    }
    return %orig;
}
%end

%hook SBExternalDisplayService
// 16.2 0x1c77d5510: the 16.0 preferredArrangementOfDisplay: body under its new name
%new
- (id)preferredArrangementOfExternalDisplay:(id)display {
    SEL old = NSSelectorFromString(@"preferredArrangementOfDisplay:");
    return (display && [self respondsToSelector:old]) ? G4B_Obj1(self, old, display) : nil;
}
// 16.2 0x1c77d5620
%new
- (id)preferredArrangementOfDisplay:(id)display relativeTo:(id)to {
    if (!display || !to) return nil;                                 // 16.2 NSAssert
    SEL wm = NSSelectorFromString(@"sb_displayWindowingMode");
    if (![display respondsToSelector:wm] || G4B_LL(display, wm) != 1 || G4B_LL(to, wm) != 1) return nil;
    SEL mainS = @selector(isMainDisplay);
    if ([to respondsToSelector:mainS] && G4B_Bool(to, mainS)) return [self preferredArrangementOfExternalDisplay:display];
    if ([display respondsToSelector:mainS] && G4B_Bool(display, mainS)) {
        id ext = [self preferredArrangementOfExternalDisplay:to];
        if (!ext) return nil;
        static const unsigned int opposite[4] = { 2, 3, 0, 1 };      // table at 0x1c7a92d90
        unsigned int e = ((unsigned int (*)(id, SEL))objc_msgSend)(ext, @selector(edge));
        double off = ((double (*)(id, SEL))objc_msgSend)(ext, @selector(offset));
        Class ic = NSClassFromString(@"SBDisplayArrangementItem") ?: NSClassFromString(@"SBExternalDisplayArrangementItem");
        SEL ini = NSSelectorFromString(@"initWithDisplayIdentity:relativeDisplayIdentity:edge:offset:");
        if (!ic || ![ic instancesRespondToSelector:ini]) return nil;
        return ((id (*)(id, SEL, id, id, unsigned int, double))objc_msgSend)([ic alloc], ini, display, to, e > 3 ? 0 : opposite[e], -off);
    }
    return nil;
}
%end

%end // G4B_Arrange

// SBDisplayArrangementItem as a runtime subclass of the 16.0 SBExternalDisplayArrangementItem (md 7.2)
static NSString *G4B_ArrangementItemDescription(id self_, SEL _cmd) {
    SEL e = @selector(edge), o = @selector(offset), d = @selector(displayIdentity), r = @selector(relativeDisplayIdentity);
    return [NSString stringWithFormat:@"<%@: %p display=%@ relativeTo=%@ edge=%u offset=%g>", NSStringFromClass(object_getClass(self_)), self_,
            G4B_Obj(self_, d), G4B_Obj(self_, r), ((unsigned int (*)(id, SEL))objc_msgSend)(self_, e), ((double (*)(id, SEL))objc_msgSend)(self_, o)];
}
static void G4B_RegisterArrangementItem(void) {
    if (NSClassFromString(@"SBDisplayArrangementItem")) return;
    Class base = NSClassFromString(@"SBExternalDisplayArrangementItem");
    if (!base) return;
    Class c = objc_allocateClassPair(base, "SBDisplayArrangementItem", 0);
    if (!c) return;
    class_addMethod(c, @selector(description), (IMP)G4B_ArrangementItemDescription, "@@:");
    objc_registerClassPair(c);
}

// ----- (item 7 ends)

// ================================================================================================================
// SETUP
// ================================================================================================================
static BOOL G4B_BuildMatches(void) {
    char buf[64] = {0};
    size_t n = sizeof buf;
    if (sysctlbyname("kern.osversion", buf, &n, NULL, 0) != 0) return NO;
    return strcmp(buf, "20A8372") == 0;
}

// Attach the BannerKit protocols (not linkable at build time) to the pill view controller.
static void G4B_AttachBannerProtocols(void) {
    Class pill = [SBExternalDisplayEducationPillViewController class];
    for (NSString *n in @[@"BNPresentableIdentifying", @"BNPresentableObserving", @"BNPresentableObservable", @"BNPresentable"]) {
        Protocol *p = NSProtocolFromString(n);
        if (p && !class_conformsToProtocol(pill, p)) class_addProtocol(pill, p);
    }
}

// Install order = the order of the md SUMMARY. Each group is installed only if its switch is on at launch (the hooks also
// re-check at call time, so a later "off" file still takes effect).
// Call from Tweak.x's %ctor after BP_BuildMatches() and the existing %init / BP_G4_Setup().
void G4B_Setup(void) {
    if (!G4B_BuildMatches()) return;
    G4B_RegisterArrangementItem();
    G4B_AttachBannerProtocols();
    if (G4B_On("arrange"))   { %init(G4B_Arrange); }
    if (G4B_On("deferact"))  { %init(G4B_DeferAct); }
    if (G4B_On("clonemirror")) { %init(G4B_Clone); }
    if (G4B_On("presubset")) { %init(G4B_PreSubset); }
    if (G4B_On("edu"))       { %init(G4B_Edu); }
    if (G4B_On("lockedptr2")) { %init(G4B_LockedPtr); }
    if (G4B_On("migrate"))   { %init(G4B_Migrate); }
    if (G4B_On("focuslock")) { %init(G4B_FocusLock); }
    BP_Log(@"group4b installed");
}

// INTEGRATION: the (empty) %ctor was removed; Tweak.x has the only %ctor and calls G4B_Setup().
