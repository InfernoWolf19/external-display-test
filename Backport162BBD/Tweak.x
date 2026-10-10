// Backport162BBD/Tweak.x  (integrated copy of Backport162/specs/group4b-backboardd.x; Makefile / plist / control are in this directory)
//
// SEPARATE Theos tweak target that runs inside backboardd (iPadOS 16.0, build 20A8372).  Daemon-side counterpart of the
// SpringBoard clone-mirroring reconstruction (specs/group4b-reconstruct.md section 1 and group4b-reconstruct.hooks.m).
// It gives the 16.0 daemon the 16.2 behaviour "the clone mirroring mode can be set PER DESTINATION DISPLAY":
//   * new MIG routines  0x5b9fa0 (set mode for destination display)  and  0x5b9fa1 (remove the request), served on the existing
//     BackBoard display service port (com.apple.backboard.display.services) by hooking the subsystem's routine lookup;
//   * the clone decision function updateClone() is hooked so that a per-display override replaces the global owner's mode.
//
// ---------------------------------------------------------------- Theos files (copy these two into the Backport162 project)
//
//   Backport162BBD.plist              (Filter: inject into backboardd only; it must NOT load in SpringBoard)
//       { Filter = { Executables = ( "backboardd" ); }; }
//
//   Makefile fragment (add next to the existing TWEAK_NAME block; ARCHS arm64e is required, the addresses are for the arm64e slice):
//       TWEAK_NAME += Backport162BBD
//       Backport162BBD_FILES = group4b-backboardd.x
//       Backport162BBD_CFLAGS = -fobjc-arc -Wall -Werror -Wno-deprecated-declarations
//       Backport162BBD_FRAMEWORKS = Foundation
//       Backport162BBD_ARCHS = arm64e
//       Backport162BBD_INSTALL_PATH = /Library/MobileSubstrate/DynamicLibraries
//       INSTALL_TARGET_PROCESSES += backboardd          # a backboardd restart is a userspace reboot-like respring: warn the user
//
//   Dopamine (rootless) injects by Filter via its own launchd/ElleKit support; backboardd is a system daemon, so the user has to
//   enable "inject into system processes" (ElleKit default: yes) and reboot userspace once after installing.
//
// ---------------------------------------------------------------- addresses (backboardd 16.0, source version 540.1.1.0.0)
//   0x1000997f4  mig routine lookup of the BKS display subsystem (subsystem struct 0x1000e56a8, ids 0x5b9168..0x5b9182)
//   0x10004c930  updateClone(BKTVOutController *c, CAWindowServerDisplay *d)           (plain C function, x0=c x1=d)
//   0x10004cffc  reapply(BKTVOutController *c)    (sweep: removeClone + updateClone for every TVOut/Wireless display)
//   0x10004ce50  BKTVOutController singleton accessor, C function taking the class in x0
// Every hook verifies the first instruction words and the build before it patches; on mismatch the tweak does nothing.
//
// Compile: -fobjc-arc -Wall -Werror (this file avoids unused statics; %orig is not used, there are no %hook blocks).

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach/mach.h>
#import <mach/mig.h>
#import <mach-o/dyld.h>
#import <dispatch/dispatch.h>
#import <sys/sysctl.h>
#import <unistd.h>
#import <string.h>
#import <stdarg.h>
#import <fcntl.h>
#if __has_include(<ptrauth.h>)
#import <ptrauth.h>
#endif
#import <substrate.h>

extern int proc_pidpath(int pid, void *buffer, uint32_t buffersize);
extern NDR_record_t NDR_record;

// ------------------------------------------------------------------------------------------------ constants

#define BPD_MSG_SET    0x5b9fa0u         // set per-destination mode      (16.0 uses ids up to 0x5b9182 in this subsystem; 0x5b9fa0 is free)
#define BPD_MSG_REMOVE 0x5b9fa1u         // remove the per-destination request
#define BPD_MAX_UUID   256u

static const uintptr_t kVM_lookup      = 0x1000997f4;
static const uintptr_t kVM_updateClone = 0x10004c930;
static const uintptr_t kVM_reapply     = 0x10004cffc;
static const uintptr_t kVM_shared      = 0x10004ce50;

// first instruction words of the targets (read from the 16.0 binary)
static const uint32_t kPrologueLookup[6]      = { 0xb9401408, 0x528dd309, 0x72bff489, 0x0b090108, 0x7100691f, 0x54000069 };
static const uint32_t kPrologueUpdateClone[6] = { 0xd503237f, 0xd10283ff, 0xa9046ffc, 0xa90567fa, 0xa9065ff8, 0xa90757f6 };
static const uint32_t kPrologueReapply[6]     = { 0xd503237f, 0xd10543ff, 0xa90f6ffc, 0xa91067fa, 0xa9115ff8, 0xa91257f6 };
static const uint32_t kPrologueShared[4]      = { 0xd503237f, 0xa9bf7bfd, 0x910003fd, 0x94013891 };

// ------------------------------------------------------------------------------------------------ logging / switches

static char gBPDDebug[1100], gBPDOff[1100], gBPDLog[1100];

static void BPD_InitPaths(void) {
    // backboardd is not rootless-path aware through <rootless.h> in every Theos version: probe both locations.
    const char *roots[2] = { "/var/jb/tmp", "/tmp" };
    for (int i = 0; i < 2; i++) {
        char probe[1100];
        snprintf(probe, sizeof probe, "%s/Backport162.off", roots[i]);
        snprintf(gBPDOff, sizeof gBPDOff, "%s", probe);
        snprintf(gBPDDebug, sizeof gBPDDebug, "%s/Backport162.debug", roots[i]);
        snprintf(gBPDLog, sizeof gBPDLog, "%s/Backport162.log", roots[i]);
        if (access(roots[i], W_OK) == 0) break;
    }
}
static BOOL BPD_Killed(void) {
    static uint64_t next; static BOOL last;
    uint64_t t = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    if (t < next) return last;
    next = t + 1000000000ull;
    char off1[1100]; snprintf(off1, sizeof off1, "%s.clonemirror", gBPDOff);
    last = (gBPDOff[0] && access(gBPDOff, F_OK) == 0) || access(off1, F_OK) == 0;
    return last;
}
static void BPD_Log(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);
static void BPD_Log(NSString *fmt, ...) {
    if (!gBPDDebug[0] || access(gBPDDebug, F_OK) != 0) return;
    va_list ap; va_start(ap, fmt);
    NSString *m = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    int fd = open(gBPDLog, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0644);
    if (fd < 0) return;
    NSString *line = [NSString stringWithFormat:@"g4b-bbd %@\n", m];
    const char *u = line.UTF8String;
    if (u) (void)!write(fd, u, strlen(u));
    close(fd);
}

// ------------------------------------------------------------------------------------------------ pointers to unexported code

static intptr_t gSlide;

static void *BPD_FnAt(uintptr_t vm) {                       // unsigned address -> callable function pointer
    void *p = (void *)(vm + (uintptr_t)gSlide);
#if __has_feature(ptrauth_calls)
    p = ptrauth_sign_unauthenticated(p, ptrauth_key_function_pointer, 0);
#endif
    return p;
}
static BOOL BPD_Verify(uintptr_t vm, const uint32_t *words, int n) {
    const uint32_t *p = (const uint32_t *)(vm + (uintptr_t)gSlide);
#if __has_feature(ptrauth_calls)
    p = ptrauth_strip(p, ptrauth_key_function_pointer);
#endif
    for (int i = 0; i < n; i++) if (p[i] != words[i]) return NO;
    return YES;
}

// ------------------------------------------------------------------------------------------------ state

static NSMutableDictionary<NSString *, NSNumber *> *gOverride;     // destination UUID -> BKS mode (2 = disabled, 1 = forced, 3 = replay)
static NSMutableDictionary<NSString *, NSNumber *> *gOwnerPid;     // destination UUID -> pid of the requesting SpringBoard
static NSMutableDictionary<NSNumber *, dispatch_source_t> *gWatch; // pid -> exit watcher
static dispatch_queue_t gStateQ;                                    // serial; protects the three dictionaries
static Class gProxyClass;

static void (*orig_updateClone)(id, id);
static void *(*orig_lookup)(mach_msg_header_t *);
static void (*fn_reapply)(id);
static id (*fn_shared)(Class);

static id BPD_Controller(void) {
    Class k = objc_getClass("BKTVOutController");
    if (!k || !fn_shared) return nil;
    return fn_shared(k);
}

static void BPD_Reapply(void) {
    id c = BPD_Controller();
    if (!c || !fn_reapply) return;
    Ivar iv = class_getInstanceVariable(object_getClass(c), "_workQueue");
    dispatch_queue_t q = iv ? (__bridge dispatch_queue_t)object_getIvar(c, iv) : nil;
    if (!q) { BPD_Log(@"no _workQueue, cannot reapply"); return; }
    dispatch_async(q, ^{ fn_reapply(c); });          // same queue the stock mirroring-mode block (0x10004ecb4) runs on
}

// proxy client: the original updateClone() asks the controller's current client for -mode; we answer with the override.
static unsigned long long BPD_ProxyMode(id self_, SEL _cmd) {
    (void)_cmd;
    NSNumber *n = objc_getAssociatedObject(self_, "bpd.mode");
    return n.unsignedLongLongValue;
}
static long long BPD_ProxyVPID(id self_, SEL _cmd) { (void)self_; (void)_cmd; return 0; }

static BOOL BPD_SetupProxyClass(void) {
    Class base = objc_getClass("_BKCloneMirroringClient");
    if (!base) return NO;
    gProxyClass = objc_allocateClassPair(base, "BPDProxyCloneClient", 0);
    if (!gProxyClass) return NO;
    class_addMethod(gProxyClass, sel_registerName("mode"), (IMP)BPD_ProxyMode, "Q16@0:8");
    class_addMethod(gProxyClass, sel_registerName("versionedPID"), (IMP)BPD_ProxyVPID, "q16@0:8");
    objc_registerClassPair(gProxyClass);
    return YES;
}

// ------------------------------------------------------------------------------------------------ hook: updateClone

static void hk_updateClone(id c, id d) {
    if (BPD_Killed() || !c || !d || !gProxyClass) { orig_updateClone(c, d); return; }
    NSString *uuid = nil;
    if ([d respondsToSelector:@selector(uniqueId)]) uuid = ((id (*)(id, SEL))objc_msgSend)(d, @selector(uniqueId));
    __block NSNumber *ov = nil;
    if ([uuid isKindOfClass:[NSString class]]) {
        dispatch_sync(gStateQ, ^{ ov = gOverride[uuid]; });
    }
    Ivar iv = class_getInstanceVariable(object_getClass(c), "_queue_currentCloneMirroringClient");
    if (!ov || !iv) { orig_updateClone(c, d); return; }
    id proxy = class_createInstance(gProxyClass, 0);         // no -init on purpose: the real init builds a port watcher
    if (!proxy) { orig_updateClone(c, d); return; }
    objc_setAssociatedObject(proxy, "bpd.mode", ov, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    void **slot = (void **)((char *)(__bridge void *)c + ivar_getOffset(iv));
    void *saved = *slot;                                       // borrowed: the controller still owns it
    *slot = (__bridge void *)proxy;                            // proxy stays alive through the local strong reference
    BPD_Log(@"updateClone %@ with override mode %@", uuid, ov);
    orig_updateClone(c, d);
    *slot = saved;
}

// ------------------------------------------------------------------------------------------------ owner tracking

static void BPD_WatchPid(pid_t pid) {                         // called on gStateQ
    NSNumber *k = @(pid);
    if (gWatch[k]) return;
    dispatch_source_t s = dispatch_source_create(DISPATCH_SOURCE_TYPE_PROC, (uintptr_t)pid, DISPATCH_PROC_EXIT, gStateQ);
    if (!s) return;
    dispatch_source_set_event_handler(s, ^{
        NSMutableArray *dead = [NSMutableArray array];
        for (NSString *u in gOwnerPid) if ([gOwnerPid[u] intValue] == pid) [dead addObject:u];
        for (NSString *u in dead) { [gOverride removeObjectForKey:u]; [gOwnerPid removeObjectForKey:u]; }
        dispatch_source_cancel(gWatch[k]);
        [gWatch removeObjectForKey:k];
        if (dead.count) { BPD_Log(@"owner pid %d exited, dropped %lu overrides", pid, (unsigned long)dead.count); BPD_Reapply(); }
    });
    gWatch[k] = s;
    dispatch_resume(s);
}

// ------------------------------------------------------------------------------------------------ the MIG routines

typedef struct {
    mach_msg_header_t Head;
    NDR_record_t      NDR;
    uint32_t          len;               // byte count of uuid including the NUL
    char              data[BPD_MAX_UUID + 8];   // uuid, padded to 4; for SET the uint32 mode follows the padded uuid
} BPDRequest;

typedef struct {
    mach_msg_header_t Head;
    NDR_record_t      NDR;
    kern_return_t     RetCode;
} BPDReply;                              // 0x24 bytes, same shape as every generated MIG reply

static void BPD_FillReply(mach_msg_header_t *in, mach_msg_header_t *out, kern_return_t kr) {
    BPDReply *r = (BPDReply *)out;
    r->Head.msgh_bits = MACH_MSGH_BITS(MACH_MSGH_BITS_REMOTE(in->msgh_bits), 0);
    r->Head.msgh_size = sizeof(BPDReply);
    r->Head.msgh_remote_port = in->msgh_remote_port;
    r->Head.msgh_local_port = MACH_PORT_NULL;
    r->Head.msgh_voucher_port = MACH_PORT_NULL;
    r->Head.msgh_id = in->msgh_id + 100;
    r->NDR = NDR_record;
    r->RetCode = kr;
}

static BOOL BPD_SenderIsSpringBoard(const audit_token_t *tok, pid_t *pidOut) {
    pid_t pid = (pid_t)tok->val[5];                                  // audit_token_to_pid
    uid_t euid = (uid_t)tok->val[1];                                 // audit_token_to_euid
    char path[1024] = {0};
    if (proc_pidpath(pid, path, sizeof path) <= 0) return NO;
    size_t n = strlen(path), s = strlen("/SpringBoard");
    if (n < s || strcmp(path + n - s, "/SpringBoard") != 0) return NO;
    if (euid != 0 && euid != 501) return NO;                          // root or mobile
    *pidOut = pid;
    return YES;
}

// mig_routine_t: void (*)(mach_msg_header_t *in, mach_msg_header_t *out)
static void BPD_Routine(mach_msg_header_t *in, mach_msg_header_t *out) {
    kern_return_t kr = KERN_SUCCESS;
    BPDRequest *q = (BPDRequest *)in;
    uint32_t size = in->msgh_size;
    BOOL isSet = (in->msgh_id == BPD_MSG_SET);
    pid_t pid = 0;
    do {
        if (BPD_Killed()) { kr = KERN_FAILURE; break; }
        if ((in->msgh_bits & MACH_MSGH_BITS_COMPLEX) || size < 0x24 || size > sizeof(BPDRequest)) { kr = MIG_BAD_ARGUMENTS; break; }
        uint32_t len = q->len;
        uint32_t padded = (len + 3u) & ~3u;
        if (len < 2 || len > BPD_MAX_UUID || (uint32_t)(0x24 + padded + (isSet ? 4 : 0)) > size) { kr = MIG_BAD_ARGUMENTS; break; }
        if (q->data[len - 1] != 0 || memchr(q->data, 0, len) != q->data + len - 1) { kr = MIG_BAD_ARGUMENTS; break; }
        // audit trailer directly behind the (4-byte rounded) message
        mach_msg_audit_trailer_t *t = (mach_msg_audit_trailer_t *)((char *)in + ((size + 3u) & ~3u));
        if (t->msgh_trailer_type != MACH_MSG_TRAILER_FORMAT_0 || t->msgh_trailer_size < sizeof(mach_msg_audit_trailer_t)) { kr = MIG_BAD_ARGUMENTS; break; }
        if (!BPD_SenderIsSpringBoard(&t->msgh_audit, &pid)) { kr = KERN_NO_ACCESS; break; }
        NSString *uuid = [NSString stringWithUTF8String:q->data];
        if (!uuid.length) { kr = MIG_BAD_ARGUMENTS; break; }
        uint32_t mode = 0;
        if (isSet) memcpy(&mode, q->data + padded, 4);
        if (isSet && (mode == 0 || mode > 3)) isSet = NO;            // BKS 0 (Default) = no override, like a remove
        BOOL wasSet = isSet;
        dispatch_sync(gStateQ, ^{
            if (wasSet) { gOverride[uuid] = @(mode); gOwnerPid[uuid] = @(pid); BPD_WatchPid(pid); }
            else { [gOverride removeObjectForKey:uuid]; [gOwnerPid removeObjectForKey:uuid]; }
        });
        BPD_Log(@"%@ %@ mode %u from pid %d", wasSet ? @"set" : @"remove", uuid, mode, pid);
        BPD_Reapply();
    } while (0);
    BPD_FillReply(in, out, kr);
}

static void *hk_lookup(mach_msg_header_t *in) {
    if (in && (in->msgh_id == BPD_MSG_SET || in->msgh_id == BPD_MSG_REMOVE)) return (void *)BPD_Routine;
    return orig_lookup(in);
}

// ------------------------------------------------------------------------------------------------ setup

static BOOL BPD_BuildMatches(void) {
    char buf[64] = {0};
    size_t n = sizeof buf;
    if (sysctlbyname("kern.osversion", buf, &n, NULL, 0) != 0) return NO;
    return strcmp(buf, "20A8372") == 0;
}

%ctor {
    @autoreleasepool {
        BPD_InitPaths();
        const char *path = _dyld_get_image_name(0);
        if (!path) return;
        size_t n = strlen(path);
        if (n < 10 || strcmp(path + n - 10, "/backboardd") != 0) return;     // belt and braces next to the Filter
        if (!BPD_BuildMatches()) { BPD_Log(@"build does not match 20A8372, not installing"); return; }
        gSlide = _dyld_get_image_vmaddr_slide(0);
        if (!BPD_Verify(kVM_lookup, kPrologueLookup, 6) || !BPD_Verify(kVM_updateClone, kPrologueUpdateClone, 6) ||
            !BPD_Verify(kVM_reapply, kPrologueReapply, 6) || !BPD_Verify(kVM_shared, kPrologueShared, 4)) {
            BPD_Log(@"prologue mismatch, not installing");
            return;
        }
        if (!BPD_SetupProxyClass()) { BPD_Log(@"_BKCloneMirroringClient missing, not installing"); return; }
        gOverride = [NSMutableDictionary dictionary];
        gOwnerPid = [NSMutableDictionary dictionary];
        gWatch = [NSMutableDictionary dictionary];
        gStateQ = dispatch_queue_create("com.apple.backboardd.Backport162.clonemirror", DISPATCH_QUEUE_SERIAL);
        fn_reapply = (void (*)(id))BPD_FnAt(kVM_reapply);
        fn_shared = (id (*)(Class))BPD_FnAt(kVM_shared);
        MSHookFunction(BPD_FnAt(kVM_updateClone), (void *)hk_updateClone, (void **)&orig_updateClone);
        MSHookFunction(BPD_FnAt(kVM_lookup), (void *)hk_lookup, (void **)&orig_lookup);
        BPD_Log(@"installed (slide 0x%lx)", (long)gSlide);
    }
}
