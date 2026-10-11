// Backport162BBD/Tweak.x
//
// SEPARATE Theos tweak target that runs inside backboardd (iPadOS 16.0, build 20A8372, arm64e).  Daemon-side counterpart of the
// SpringBoard clone-mirroring port (Backport162/G4B.x, group "clonemirror").
//
// It ports the 16.2 (20C65) backboardd feature "the clone mirroring mode can be requested PER DESTINATION DISPLAY".  What 16.2
// backboardd does (read from the 16.2 binary, source version of the 16.2 build; see Backport162/specs/PORT-group4-0.7.0.md):
//   * two new MIG routines on the BackBoard display service (com.apple.backboard.display.services):
//         SetCloneMirroringModeForDestinationDisplay(displayUUID, mode)   mode 0..3 (default, force, disable, replay)
//         RemoveCloneMirroringModeForDestinationDisplay(displayUUID)
//     both identified per calling process (pid), both answered after the request cache was updated;
//   * BKDisplayCloneMirrorRequestCache: pid -> (uuid -> request), an ordered list of all requests, a "prevailing" table
//     uuid -> request (the OLDEST request of a destination wins; a newer request of the SAME process replaces its own),
//     rebuilt from the ordered list whenever a request is removed; the requests of a process are dropped when it exits;
//   * updateClone(): mode = prevailing[display.uniqueId] ?: the global client's mode ?: 0 (default); everything after that
//     (CarPlay / self / defaults / tethering / addClone options / tag bits) is the unchanged 16.0 decision tree.
//
// 16.0 serves ids 0x5b9168..0x5b9182 of that port; 0x5b9fa0 / 0x5b9fa1 are free.  16.0 backboardd serves the port with a
// dispatch_mach channel whose handler (0x100026d14) calls dispatch_mach_mig_demux(NULL, &subsystem, 1, dmsg) and destroys
// the message when the demux says "not mine".  The demux selects the routine by the subsystem's start/end RANGE and never
// calls subsystem->server, so hooking the routine lookup (0x1000997f4, the first version of this tweak) never fired.
// This version hooks the HANDLER function itself: for reason 2 (message received) and a message id of ours it validates the
// request, updates the cache and sends the reply exactly like the demux would; everything else goes to the original handler.
//
// Safety: nothing is patched unless the build string is 20A8372, the process is backboardd, every patched function starts
// with the expected instruction words and the subsystem table has the expected start id.  Every failure returns with a log
// line (only when /var/jb/tmp/Backport162.debug exists); there is no loop and no exception.
//
// Theos: Filter plist (backboardd only), Makefile and control are in this directory.  backboardd is a system daemon, so a
// userspace reboot is needed once after installing.
//
// ---------------------------------------------------------------- addresses (backboardd 16.0, unslid file vmaddrs)
//   0x100026d14  dispatch_mach handler  void (void *ctx /*subsystem*/, unsigned long reason, dispatch_mach_msg_t, int error)
//   0x1000e56a8  mig_subsystem of the BKS display service (start 0x5b9168)
//   0x10004c930  updateClone(BKTVOutController *c, CAWindowServerDisplay *d)           (plain C function, x0=c x1=d)
//   0x10004cffc  reapply(BKTVOutController *c)    (sweep: removeClone + updateClone for every TVOut/Wireless display)
//   0x10004ce50  BKTVOutController singleton accessor, C function taking the class in x0
//
// Compile: -fobjc-arc -Wall -Werror.

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
#import <pthread.h>
#import <signal.h>
#import <errno.h>
#import <dlfcn.h>
#if __has_include(<ptrauth.h>)
#import <ptrauth.h>
#endif
#import <substrate.h>

extern int proc_pidpath(int pid, void *buffer, uint32_t buffersize);
extern NDR_record_t NDR_record;

// ------------------------------------------------------------------------------------------------ constants

#define BPD_MSG_SET    0x5b9fa0u         // set the mode request of the calling process for a destination display
#define BPD_MSG_REMOVE 0x5b9fa1u         // remove it
#define BPD_MAX_UUID   256u
#define BPD_SUBSYSTEM_START 0x5b9168u

static const uintptr_t kVM_handler     = 0x100026d14;
static const uintptr_t kVM_subsystem   = 0x1000e56a8;
static const uintptr_t kVM_updateClone = 0x10004c930;
static const uintptr_t kVM_reapply     = 0x10004cffc;
static const uintptr_t kVM_shared      = 0x10004ce50;

// first instruction words of the targets (read from the 16.0 binary)
static const uint32_t kPrologueHandler[6]     = { 0xd503237f, 0xd10103ff, 0xa90157f6, 0xa9024ff4, 0xa9037bfd, 0x9100c3fd };
static const uint32_t kPrologueUpdateClone[6] = { 0xd503237f, 0xd10283ff, 0xa9046ffc, 0xa90567fa, 0xa9065ff8, 0xa90757f6 };
static const uint32_t kPrologueReapply[6]     = { 0xd503237f, 0xd10543ff, 0xa90f6ffc, 0xa91067fa, 0xa9115ff8, 0xa91257f6 };
static const uint32_t kPrologueShared[4]      = { 0xd503237f, 0xa9bf7bfd, 0x910003fd, 0x94013891 };

// ------------------------------------------------------------------------------------------------ logging / switches

static char gBPDDebug[1100], gBPDOff[1100], gBPDLog[1100];

static void BPD_InitPaths(void) {
    // Dopamine is rootless: /var/jb/tmp is where SpringBoard's tweak looks (jbroot/tmp); /tmp only as a last resort.
    const char *root = (access("/var/jb/tmp", F_OK) == 0) ? "/var/jb/tmp" : "/tmp";
    snprintf(gBPDOff, sizeof gBPDOff, "%s/Backport162.off", root);
    snprintf(gBPDDebug, sizeof gBPDDebug, "%s/Backport162.debug", root);
    snprintf(gBPDLog, sizeof gBPDLog, "%s/Backport162.log", root);
}
static BOOL BPD_Killed(void) {
    static uint64_t next; static BOOL last;
    uint64_t t = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    if (t < next) return last;
    next = t + 1000000000ull;
    char off1[1200]; snprintf(off1, sizeof off1, "%s.clonemirror", gBPDOff);
    last = (gBPDOff[0] && access(gBPDOff, F_OK) == 0) || access(off1, F_OK) == 0;
    return last;
}
static BOOL BPD_LogOn(void) {
    static uint64_t next; static BOOL last;
    uint64_t t = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    if (t < next) return last;
    next = t + 1000000000ull;
    last = gBPDDebug[0] && access(gBPDDebug, F_OK) == 0;
    return last;
}
static void BPD_Log(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);
static void BPD_Log(NSString *fmt, ...) {
    if (!BPD_LogOn()) return;
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

#if __has_feature(ptrauth_calls)
#define BPD_STRIP(p) ptrauth_strip((p), ptrauth_key_function_pointer)
#define BPD_SIGN(p)  ptrauth_sign_unauthenticated(ptrauth_strip((p), ptrauth_key_function_pointer), ptrauth_key_function_pointer, 0)
#else
#define BPD_STRIP(p) (p)
#define BPD_SIGN(p)  (p)
#endif

static void *BPD_FnAt(uintptr_t vm) {                       // unsigned address -> callable function pointer
    return BPD_SIGN((void *)(vm + (uintptr_t)gSlide));
}
static BOOL BPD_Verify(uintptr_t vm, const uint32_t *words, int n) {
    const uint32_t *p = (const uint32_t *)(vm + (uintptr_t)gSlide);
    for (int i = 0; i < n; i++) if (p[i] != words[i]) return NO;
    return YES;
}

typedef mach_msg_header_t *(*BPD_GetMsg_t)(void *dmsg, size_t *sizep);                 // dispatch_mach_msg_get_msg
typedef void (*BPD_Handler_t)(void *ctx, unsigned long reason, void *dmsg, int error);
typedef void (*BPD_UpdateClone_t)(id, id);

static BPD_GetMsg_t      fn_getMsg;
static BPD_Handler_t     orig_handler;
static BPD_UpdateClone_t orig_updateClone;
static void (*fn_reapply)(id);
static id (*fn_shared)(Class);
static void *gSubsystem;                                    // slid address of the BKS display service's mig_subsystem

// ------------------------------------------------------------------------------------------------ request cache (16.2 BKDisplayCloneMirrorRequestCache)

@interface BPDReq : NSObject
@property (nonatomic) int pid;
@property (nonatomic, copy) NSString *uuid;
@property (nonatomic) unsigned long long mode;
@end
@implementation BPDReq
- (NSString *)description { return [NSString stringWithFormat:@"<pid %d %@ mode %llu>", self.pid, self.uuid, self.mode]; }
@end

// object the patched updateClone() finds in controller._queue_currentCloneMirroringClient while a per-destination request applies
@interface BPDModeProxy : NSObject
@property (nonatomic) unsigned long long mode;
@end
@implementation BPDModeProxy
- (long long)versionedPID { return 0; }
@end

static pthread_mutex_t gLock = PTHREAD_MUTEX_INITIALIZER;          // protects the four containers below (16.2: os_unfair_lock at cache+8)
static NSMutableArray<BPDReq *> *gOrdered;                          // 16.2 cache+0x28: all requests in arrival order
static NSMutableDictionary<NSNumber *, NSMutableDictionary<NSString *, BPDReq *> *> *gByPid;   // cache+0x20
static NSMutableDictionary<NSString *, BPDReq *> *gPrevailing;      // cache+0x18: destination uuid -> the request that applies
static NSMutableDictionary<NSNumber *, dispatch_source_t> *gWatch;  // cache+0x30: pid -> exit watcher

static pthread_mutex_t gHookLock;                                   // serialises the temporary ivar swap in hk_updateClone (recursive)

static void BPD_Reapply(void);

// 16.2 -_lock_rebuildModeCache (0x10002f23c): first request in arrival order wins per destination
static void BPD_RebuildLocked(void) {
    NSMutableDictionary<NSString *, BPDReq *> *n = [NSMutableDictionary dictionary];
    for (BPDReq *r in gOrdered) if (r.uuid && !n[r.uuid]) n[r.uuid] = r;
    gPrevailing = n;
    BPD_Log(@"clone mirror cache is now %@", n);
}

// 16.2 set block (0x10004f7e0)
static void BPD_SetLocked(int pid, NSString *uuid, unsigned long long mode, void (^watch)(int)) {
    BPDReq *r = [BPDReq new];
    r.pid = pid; r.uuid = uuid; r.mode = mode;
    NSNumber *pk = @(pid);
    NSMutableDictionary<NSString *, BPDReq *> *d = gByPid[pk];
    if (d) {
        BPDReq *old = d[uuid];
        if (old) [gOrdered removeObject:old];
        d[uuid] = r;
    } else {
        gByPid[pk] = [NSMutableDictionary dictionaryWithObject:r forKey:uuid];
        watch(pid);                                                 // 16.2 _lock_addDeathWatcherForPid:
    }
    [gOrdered addObject:r];
    BPDReq *p = gPrevailing[uuid];
    if (!p || p.pid == pid) gPrevailing[uuid] = r;                  // an older request of another process keeps priority
}

// 16.2 remove block (0x10004faf8)
static void BPD_RemoveLocked(int pid, NSString *uuid) {
    NSNumber *pk = @(pid);
    NSMutableDictionary<NSString *, BPDReq *> *d = gByPid[pk];
    BPDReq *old = d[uuid];
    if (old) {
        [gOrdered removeObject:old];
        [d removeObjectForKey:uuid];
    }
    if (d.count == 0) {
        [gByPid removeObjectForKey:pk];
        dispatch_source_t s = gWatch[pk];
        if (s) { dispatch_source_cancel(s); [gWatch removeObjectForKey:pk]; }
    }
    BPD_RebuildLocked();
}

// 16.2 "clone mirror remove all for pid %d" (0x10002f524)
static void BPD_RemoveAllLocked(int pid) {
    BPD_Log(@"clone mirror remove all for pid %d", pid);
    NSNumber *pk = @(pid);
    NSMutableDictionary<NSString *, BPDReq *> *d = gByPid[pk];
    if (d) {
        [gOrdered removeObjectsInArray:d.allValues];
        [gByPid removeObjectForKey:pk];
    }
    dispatch_source_t s = gWatch[pk];
    if (s) { dispatch_source_cancel(s); [gWatch removeObjectForKey:pk]; }
    BPD_RebuildLocked();
}

static void BPD_WatchPidLocked(int pid) {
    NSNumber *k = @(pid);
    if (gWatch[k]) return;
    if (kill((pid_t)pid, 0) != 0 && errno == ESRCH) {               // already gone: nothing to watch, drop right away
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            pthread_mutex_lock(&gLock); BPD_RemoveAllLocked(pid); pthread_mutex_unlock(&gLock);
            BPD_Reapply();
        });
        return;
    }
    dispatch_source_t s = dispatch_source_create(DISPATCH_SOURCE_TYPE_PROC, (uintptr_t)pid, DISPATCH_PROC_EXIT, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
    if (!s) return;
    dispatch_source_set_event_handler(s, ^{
        pthread_mutex_lock(&gLock);
        BPD_RemoveAllLocked(pid);
        pthread_mutex_unlock(&gLock);
        BPD_Reapply();
    });
    gWatch[k] = s;
    dispatch_resume(s);
}

// ------------------------------------------------------------------------------------------------ re-evaluation of all displays

static id BPD_Controller(void) {
    Class k = objc_getClass("BKTVOutController");
    if (!k || !fn_shared) return nil;
    return fn_shared(k);
}
static void BPD_Reapply(void) {
    @autoreleasepool {
        id c = BPD_Controller();
        if (!c || !fn_reapply) return;
        Ivar iv = class_getInstanceVariable(object_getClass(c), "_workQueue");
        dispatch_queue_t q = iv ? (dispatch_queue_t)object_getIvar(c, iv) : nil;
        if (!q) { BPD_Log(@"no _workQueue, cannot reapply"); return; }
        void (*fn)(id) = fn_reapply;
        dispatch_async(q, ^{ fn(c); });                             // same queue the stock mirroring-mode block (0x10004ecb4) runs on
    }
}

// ------------------------------------------------------------------------------------------------ hook: updateClone

// 16.2 updateClone: mode = prevailing[display.uniqueId] ?: global client mode ?: default.  16.0's body reads the mode with
// [controller._queue_currentCloneMirroringClient mode] and then runs the unchanged decision tree, so the prevailing request is
// presented through that one ivar for the duration of the call (all callers run on controller._workQueue; the lock below covers
// any other caller).
static void hk_updateClone(id c, id d) {
    if (BPD_Killed() || !c || !d) { orig_updateClone(c, d); return; }
    NSString *uuid = nil;
    if ([d respondsToSelector:@selector(uniqueId)]) uuid = ((id (*)(id, SEL))objc_msgSend)(d, @selector(uniqueId));
    BPDReq *req = nil;
    if ([uuid isKindOfClass:[NSString class]]) {
        pthread_mutex_lock(&gLock);
        req = gPrevailing[uuid];
        pthread_mutex_unlock(&gLock);
    }
    Ivar iv = req ? class_getInstanceVariable(object_getClass(c), "_queue_currentCloneMirroringClient") : NULL;
    pthread_mutex_lock(&gHookLock);                                 // also for the pass-through case: nobody may read the ivar mid-swap
    if (!req || !iv) { orig_updateClone(c, d); pthread_mutex_unlock(&gHookLock); return; }
    BPDModeProxy *proxy = [BPDModeProxy new];
    proxy.mode = req.mode;
    CFTypeRef held = CFBridgingRetain(proxy);                       // keeps the proxy alive across the call (ARC may release after the last use)
    void **slot = (void **)((char *)(__bridge void *)c + ivar_getOffset(iv));
    void *saved = *slot;                                            // borrowed: the controller still owns it
    *slot = (void *)held;
    BPD_Log(@"updateClone %@ prevailing mode %llu (pid %d)", uuid, req.mode, req.pid);
    orig_updateClone(c, d);
    *slot = saved;
    CFRelease(held);
    pthread_mutex_unlock(&gHookLock);
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

// validates and executes one request; returns the MIG return code
static kern_return_t BPD_Execute(mach_msg_header_t *in) {
    BPDRequest *q = (BPDRequest *)in;
    uint32_t size = in->msgh_size;
    BOOL isSet = (in->msgh_id == BPD_MSG_SET);
    if (BPD_Killed()) return KERN_FAILURE;
    if ((in->msgh_bits & MACH_MSGH_BITS_COMPLEX) || size < 0x24 || size > sizeof(BPDRequest)) return MIG_BAD_ARGUMENTS;
    uint32_t len = q->len;
    uint32_t padded = (len + 3u) & ~3u;
    // 16.2: "empty displayUUID not allowed"
    if (len < 2 || len > BPD_MAX_UUID || (uint32_t)(0x24 + padded + (isSet ? 4 : 0)) > size) return MIG_BAD_ARGUMENTS;
    if (q->data[len - 1] != 0 || memchr(q->data, 0, len) != q->data + len - 1) return MIG_BAD_ARGUMENTS;
    // audit trailer directly behind the (4-byte rounded) message; the stock stubs read it the same way
    mach_msg_audit_trailer_t *t = (mach_msg_audit_trailer_t *)((char *)in + ((size + 3u) & ~3u));
    if (t->msgh_trailer_type != MACH_MSG_TRAILER_FORMAT_0 || t->msgh_trailer_size < sizeof(mach_msg_audit_trailer_t)) return MIG_BAD_ARGUMENTS;
    pid_t pid = 0;
    if (!BPD_SenderIsSpringBoard(&t->msgh_audit, &pid)) return KERN_NO_ACCESS;
    NSString *uuid = [NSString stringWithUTF8String:q->data];
    if (!uuid.length) return MIG_BAD_ARGUMENTS;
    uint32_t mode = 0;
    if (isSet) {
        memcpy(&mode, q->data + padded, 4);
        if (mode > 3) { BPD_Log(@"SetCloneMirroringModeForDestinationDisplay: unknown mode value %X", mode); return MIG_BAD_ARGUMENTS; }   // 16.2 log + return
    }
    pthread_mutex_lock(&gLock);
    if (isSet) {
        BPD_Log(@"clone mirror mode request:%u destinationDisplay:%@ from pid:%d", mode, uuid, pid);
        BPD_SetLocked(pid, uuid, mode, ^(int p) { BPD_WatchPidLocked(p); });
    } else {
        BPD_Log(@"clone mirror mode remove for destinationDisplay:%@ from pid:%d", uuid, pid);
        BPD_RemoveLocked(pid, uuid);
    }
    pthread_mutex_unlock(&gLock);
    BPD_Reapply();                                                   // 16.2: delegate cloneMirroringRequestsDidChange
    return KERN_SUCCESS;
}

// What dispatch_mach_mig_demux does around a routine (libdispatch 16.0 0x18e12c570..0x18e12c694), for our two ids.
static void BPD_Serve(mach_msg_header_t *hdr) {
    BPDReply reply;
    memset(&reply, 0, sizeof reply);
    reply.Head.msgh_bits = hdr->msgh_bits & 0x1f;
    reply.Head.msgh_size = sizeof reply;
    reply.Head.msgh_remote_port = hdr->msgh_remote_port;
    reply.Head.msgh_id = hdr->msgh_id + 100;
    kern_return_t kr = BPD_Execute(hdr);
    reply.NDR = NDR_record;
    reply.RetCode = kr;
    if (kr != KERN_SUCCESS) {                                        // demux: drop the request's reply right from the request, destroy the rest
        hdr->msgh_remote_port = MACH_PORT_NULL;
        mach_msg_destroy(hdr);
    }
    if (reply.Head.msgh_remote_port) {
        mach_msg_option_t opt = ((reply.Head.msgh_bits & 0x1f) == MACH_MSG_TYPE_MOVE_SEND_ONCE) ? MACH_SEND_MSG : (MACH_SEND_MSG | MACH_SEND_TIMEOUT);
        kern_return_t sk = mach_msg(&reply.Head, opt, sizeof reply, 0, MACH_PORT_NULL, 0, MACH_PORT_NULL);
        if (sk != KERN_SUCCESS) {
            BPD_Log(@"reply send failed 0x%x", sk);
            mach_msg_destroy(&reply.Head);
        }
    }
}

static void hk_handler(void *ctx, unsigned long reason, void *dmsg, int error) {
    if (reason == 2 && dmsg && ctx && ctx == gSubsystem && fn_getMsg) {        // 2 = DISPATCH_MACH_MESSAGE_RECEIVED
        mach_msg_header_t *hdr = fn_getMsg(dmsg, NULL);
        if (hdr && (hdr->msgh_id == (mach_msg_id_t)BPD_MSG_SET || hdr->msgh_id == (mach_msg_id_t)BPD_MSG_REMOVE)) {
            @autoreleasepool { BPD_Serve(hdr); }
            return;
        }
    }
    orig_handler(ctx, reason, dmsg, error);
}

// ------------------------------------------------------------------------------------------------ setup

static BOOL BPD_BuildMatches(void) {
    char buf[64] = {0};
    size_t n = sizeof buf;
    if (sysctlbyname("kern.osversion", buf, &n, NULL, 0) != 0) return NO;
    return strcmp(buf, "20A8372") == 0;
}

static void BPD_Hook(uintptr_t vm, void *replacement, void **origOut) {
    void *target = BPD_STRIP((void *)(vm + (uintptr_t)gSlide));
    void *orig = NULL;
    MSHookFunction(target, BPD_STRIP(replacement), &orig);
    *origOut = orig ? BPD_SIGN(orig) : NULL;
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
        if (!BPD_Verify(kVM_handler, kPrologueHandler, 6) || !BPD_Verify(kVM_updateClone, kPrologueUpdateClone, 6) ||
            !BPD_Verify(kVM_reapply, kPrologueReapply, 6) || !BPD_Verify(kVM_shared, kPrologueShared, 4)) {
            BPD_Log(@"prologue mismatch, not installing");
            return;
        }
        gSubsystem = (void *)(kVM_subsystem + (uintptr_t)gSlide);
        if (*(const uint32_t *)((const char *)gSubsystem + 8) != BPD_SUBSYSTEM_START) { BPD_Log(@"subsystem table mismatch, not installing"); return; }
        fn_getMsg = (BPD_GetMsg_t)dlsym(RTLD_DEFAULT, "dispatch_mach_msg_get_msg");
        if (!fn_getMsg) { BPD_Log(@"dispatch_mach_msg_get_msg missing, not installing"); return; }
        if (!objc_getClass("BKTVOutController")) { BPD_Log(@"BKTVOutController missing, not installing"); return; }
        gOrdered = [NSMutableArray array];
        gByPid = [NSMutableDictionary dictionary];
        gPrevailing = [NSMutableDictionary dictionary];
        gWatch = [NSMutableDictionary dictionary];
        pthread_mutexattr_t at;
        pthread_mutexattr_init(&at);
        pthread_mutexattr_settype(&at, PTHREAD_MUTEX_RECURSIVE);
        pthread_mutex_init(&gHookLock, &at);
        pthread_mutexattr_destroy(&at);
        fn_reapply = (void (*)(id))BPD_FnAt(kVM_reapply);
        fn_shared = (id (*)(Class))BPD_FnAt(kVM_shared);
        // updateClone first: a request can only be accepted once the decision function honours it
        BPD_Hook(kVM_updateClone, (void *)hk_updateClone, (void **)&orig_updateClone);
        if (!orig_updateClone) { BPD_Log(@"updateClone hook failed, not serving the routines"); return; }
        BPD_Hook(kVM_handler, (void *)hk_handler, (void **)&orig_handler);
        if (!orig_handler) { BPD_Log(@"handler hook failed"); return; }
        BPD_Log(@"installed (slide 0x%lx)", (long)gSlide);
    }
}
