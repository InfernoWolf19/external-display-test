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
#if __has_include(<rootless.h>)
#import <rootless.h>
#endif
#ifndef BP_G4B_STANDALONE
#import "BP.h"
#endif

// ------------------------------------------------------------------------------------------------ host integration

#ifdef BP_G4B_STANDALONE
static void BP_Log(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);
static void BP_Log(NSString *fmt, ...) { (void)fmt; }
#endif

// default-on switch with off files (Backport162.off, Backport162.off.<name>), cached one second per name
static BOOL G4B_On(const char *name) {
#ifdef BP_G4B_STANDALONE
    (void)name;
    return YES;
#else
    static char base[1024];
    static dispatch_once_t once;
    dispatch_once(&once, ^{
#if defined(ROOT_PATH_NS)
        snprintf(base, sizeof base, "%s", ROOT_PATH_NS(@"/tmp").fileSystemRepresentation);
#else
        snprintf(base, sizeof base, "/var/jb/tmp");
#endif
    });
    static struct { const char *name; uint64_t next; BOOL last; } slots[16];
    static uint64_t killNext; static BOOL killLast;
    uint64_t t = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    if (t >= killNext) {
        char p[1100]; snprintf(p, sizeof p, "%s/Backport162.off", base);
        killLast = access(p, F_OK) == 0;
        killNext = t + 1000000000ull;
    }
    if (killLast) return NO;
    int i = 0;
    while (i < 16 && slots[i].name && strcmp(slots[i].name, name) != 0) i++;
    if (i == 16) return NO;
    if (!slots[i].name) slots[i].name = name;
    if (t < slots[i].next) return !slots[i].last;
    slots[i].next = t + 1000000000ull;
    char p[1100]; snprintf(p, sizeof p, "%s/Backport162.off.%s", base, name);
    slots[i].last = access(p, F_OK) == 0;
    return !slots[i].last;
#endif
}

// `type`, `count` ... are declared with different return types in Foundation: message explicitly when needed.
static inline long long G4B_LL(id obj, SEL sel) { return ((long long (*)(id, SEL))objc_msgSend)(obj, sel); }
static inline BOOL G4B_Bool(id obj, SEL sel) { return ((BOOL (*)(id, SEL))objc_msgSend)(obj, sel); }
static inline id G4B_Obj(id obj, SEL sel) { return ((id (*)(id, SEL))objc_msgSend)(obj, sel); }
static inline id G4B_Obj1(id obj, SEL sel, id a) { return ((id (*)(id, SEL, id))objc_msgSend)(obj, sel, a); }

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

// @@PRIVATE_DECLS@@

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
    return %orig ^ ([self cloneMirroringMode] * 0x9e3779b97f4a7c15ull);
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
