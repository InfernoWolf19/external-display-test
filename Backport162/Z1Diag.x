// Z1Diag.x : always-on, tiny, side-effect-free instruments for the "slow touch / dead system gestures after hours" report.
// Spec: specs/DIAG-0.7.9.md (what each file holds, how to read it, cost, unproven items); plan: specs/FINDINGS-SLOWTOUCH-0.7.9.md section 5.1 items 1-4.
// Switch: diag (default ON; kill file <jbroot>/tmp/Backport162.off.diag, cached one second, so it also works at run time). Setup: Z1_Setup() (called last from the %ctor of Tweak.x).
// NO Backport162.debug needed: the files below are written whenever the switch is on.
//
//   1  stall watchdog   <jbroot>/tmp/Backport162.stall.log   plain pthread; pings the main queue every 250 ms; ping outstanding > 1.0 s -> ONE sample of the main thread
//                                                            (thread_suspend / thread_get_state / fp walk / thread_resume), written after the resume; `stall ended after N ms`
//   2  touch latency    (same file)                          SpringBoard sendEvent: hook; touches events later than 300 ms, max 1 line/s
//   3  vitals           <jbroot>/tmp/Backport162.vitals.log  one line a minute on the main queue (footprint, threads, fds, mach ports, windows, gesture collections)
//   4  state dump       <jbroot>/tmp/Backport162.state.txt   on `notifyutil -p com.infernowolf19.backport162.dumpstate`, handled on the main queue
//
// Hard rules of this file:
//   * while the main thread is suspended (Z1_TakeSample, between thread_suspend and thread_resume) the sampler only calls thread_get_state, does integer arithmetic and reads
//     the suspended thread's own stack words: no malloc, no ObjC, no locks, no printf, no dyld / dladdr, no logging. All function pointers are resolved before (dlsym), so no
//     lazy-binding stub (which would take dyld locks) can run in the window. Everything is formatted and written after the resume. The resume is on the only path that follows
//     a successful suspend (no early return in between).
//   * every file is capped at 256 KiB (truncated to zero, then the image header is written again), every collection read is bounded, every ObjC access is guarded by
//     respondsToSelector / ivar lookup by name / @try, and runs on the main queue (vitals, dump, probe), never on the watchdog thread.
//   * nothing here changes behaviour: no hook calls anything but %orig after reading; the sendEvent: hook measures and forwards.
//
// Why the touch probe hooks SpringBoard and not UIApplication: Group4Focus.x already has `%hook SpringBoard - sendEvent:` (SpringBoard has no own sendEvent: in 16.0, so the
// hook ADDS the method and captures UIApplication's implementation at that moment). A later hook of -[UIApplication sendEvent:] would be bypassed by that captured pointer, and a
// hook installed earlier is not guaranteed. A second hook of the same SpringBoard method from another group stacks correctly (the method is then the class's own, the later
// hook calls the earlier one as %orig), and as the last one installed (Z1_Setup is the last call of the %ctor) it runs first, i.e. it measures before any other code of ours.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dispatch/dispatch.h>
#import <mach/mach.h>
#import <mach/mach_time.h>
#import <mach-o/dyld.h>
#import <pthread.h>
#import <pthread/qos.h>
#import <stdatomic.h>
#import <stdarg.h>
#import <notify.h>
#import <dlfcn.h>
#import <fcntl.h>
#import <errno.h>
#import <sys/stat.h>
#import <sys/sysctl.h>
#import <sys/time.h>
#import <time.h>
#import <unistd.h>
#import <rootless.h>
#import "BP.h"

#if defined(__has_feature)
#if __has_feature(ptrauth_calls)
#include <ptrauth.h>
#define Z1_STRIP(x) ((uint64_t)(uintptr_t)ptrauth_strip((void *)(uintptr_t)(x), ptrauth_key_return_address))
#endif
#endif
#ifndef Z1_STRIP
#define Z1_STRIP(x) ((uint64_t)(x))
#endif

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

@interface SpringBoard : UIApplication @end

// ---------------------------------------------------------------- constants and state

enum {
    kZ1FileCap       = 256 * 1024,      // stall.log / vitals.log: truncated to zero beyond this
    kZ1DumpCap       = 1024 * 1024,     // state.txt (rewritten on every request)
    kZ1MaxFrames     = 16,
    kZ1PollUs        = 250 * 1000,      // watchdog period
    kZ1SamplesPerHr  = 20,
    kZ1LinesPerHr    = 60,              // stall begin lines per hour (a begin line is also written when the sample budget is used up)
};
#define Z1_STALL_NS   1000000000ull     // ping outstanding longer than this = stall
#define Z1_HOUR_NS    3600000000000ull
#define Z1_TOUCH_SEC  0.30              // touch latency threshold

static char gZ1StallPath[1000], gZ1VitalsPath[1000], gZ1StatePath[1000];
static char gZ1Hdr[3072];                                  // process start + image slides; written to the stall log at start and again after a truncation
static pthread_mutex_t gZ1FileMu = PTHREAD_MUTEX_INITIALIZER;

static _Atomic uint64_t gZ1PingAt;                         // uptime ns of the ping that has not been answered (0 = none outstanding)
static _Atomic uint64_t gZ1PongAt;                         // uptime ns when the main queue last answered
static _Atomic int gZ1InStall;                             // watchdog: a stall is open (sample taken or budget used up)
static _Atomic uint64_t gZ1StallCount, gZ1LastStallMs, gZ1LastStallEndNs, gZ1TouchLatCount;
static _Atomic uint32_t gZ1MainThread;                     // mach_thread_self() of the main thread (0 until captured)
static uint64_t gZ1MainStackHi, gZ1MainStackLo;            // written before gZ1MainThread is published
static uint64_t gZ1StartMono, gZ1StartAwake;               // CLOCK_MONOTONIC (counts sleep) / CLOCK_UPTIME_RAW at setup
static dispatch_source_t gZ1Timer;
static int gZ1DumpToken;

static kern_return_t (*gZ1Suspend)(thread_act_t);
static kern_return_t (*gZ1Resume)(thread_act_t);
static kern_return_t (*gZ1GetState)(thread_act_t, thread_state_flavor_t, thread_state_t, mach_msg_type_number_t *);

static inline uint64_t Z1_Now(void) { return clock_gettime_nsec_np(CLOCK_UPTIME_RAW); }

// Switch `diag`, cached one second here (BP_OnName takes a mutex and does two access() calls).
static BOOL Z1_Enabled(void) {
    static _Atomic uint64_t next;
    static _Atomic int on = 1;
    uint64_t n = Z1_Now();
    if (n >= atomic_load_explicit(&next, memory_order_relaxed)) {
        atomic_store_explicit(&next, n + 1000000000ull, memory_order_relaxed);
        atomic_store_explicit(&on, BP_OnName("diag") ? 1 : 0, memory_order_relaxed);
    }
    return atomic_load_explicit(&on, memory_order_relaxed) != 0;
}

// ---------------------------------------------------------------- small C helpers (no ObjC)

static void Z1_Cat(char *buf, size_t cap, size_t *off, const char *fmt, ...) __attribute__((format(printf, 4, 5)));
static void Z1_Cat(char *buf, size_t cap, size_t *off, const char *fmt, ...) {
    if (*off + 1 >= cap) return;
    va_list ap;
    va_start(ap, fmt);
    int r = vsnprintf(buf + *off, cap - *off, fmt, ap);
    va_end(ap);
    if (r <= 0) return;
    size_t room = cap - *off - 1;
    *off += ((size_t)r < room) ? (size_t)r : room;
}

static void Z1_Stamp(char *buf, size_t cap, size_t *off) {
    struct timespec ts;
    struct tm tmv;
    clock_gettime(CLOCK_REALTIME, &ts);
    localtime_r(&ts.tv_sec, &tmv);
    Z1_Cat(buf, cap, off, "%02d:%02d:%02d.%03ld ", tmv.tm_hour, tmv.tm_min, tmv.tm_sec, (long)(ts.tv_nsec / 1000000));
}

// Append to a capped file. withHdr: after a truncation write the image header again (stall log).
static void Z1_Append(const char *path, const char *data, size_t len, BOOL withHdr) {
    if (!path[0] || !data || !len) return;
    pthread_mutex_lock(&gZ1FileMu);
    int fd = open(path, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0644);
    if (fd >= 0) {
        struct stat st;
        if (fstat(fd, &st) == 0 && st.st_size > kZ1FileCap && ftruncate(fd, 0) == 0) {
            static const char m[] = "(file reached 256 KiB: truncated)\n";
            (void)!write(fd, m, sizeof m - 1);
            if (withHdr && gZ1Hdr[0]) (void)!write(fd, gZ1Hdr, strlen(gZ1Hdr));
        }
        (void)!write(fd, data, len);
        close(fd);
    }
    pthread_mutex_unlock(&gZ1FileMu);
}

// One stamped line to the stall log.
static void Z1_StallLine(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
static void Z1_StallLine(const char *fmt, ...) {
    char b[1024];
    size_t o = 0;
    Z1_Stamp(b, sizeof b, &o);
    va_list ap;
    va_start(ap, fmt);
    int r = vsnprintf(b + o, sizeof b - o - 2, fmt, ap);
    va_end(ap);
    if (r > 0) o += ((size_t)r < sizeof b - o - 2) ? (size_t)r : sizeof b - o - 3;
    b[o++] = '\n';
    Z1_Append(gZ1StallPath, b, o, YES);
}

static const char *Z1_BaseName(const char *p) {
    const char *s = p ? strrchr(p, '/') : NULL;
    return s ? s + 1 : (p ? p : "?");
}

// Process start header: build, pid, and base / slide of the images a stack is symbolicated against (the shared cache images share one slide).
static void Z1_BuildHeader(void) {
    char osv[40] = {0};
    size_t n = sizeof osv - 1;
    if (sysctlbyname("kern.osversion", osv, &n, NULL, 0) != 0) snprintf(osv, sizeof osv, "?");
    size_t off = 0;
    Z1_Cat(gZ1Hdr, sizeof gZ1Hdr, &off, "--- process start pid=%d os=%s (the LAST header of this file belongs to the running process; address - slide = address in the cache of that build) ---\n", (int)getpid(), osv);
    uint32_t cnt = _dyld_image_count();
    for (uint32_t i = 0; i < cnt; i++) {
        const char *name = _dyld_get_image_name(i);
        if (!name) continue;
        const char *b = Z1_BaseName(name);
        BOOL want = (i == 0) || strcmp(b, "UIKitCore") == 0 || strcmp(b, "SpringBoard") == 0 || strcmp(b, "BackBoardServices") == 0 || strcmp(b, "Backport162.dylib") == 0;
        if (!want) continue;
        Z1_Cat(gZ1Hdr, sizeof gZ1Hdr, &off, "image %s%s hdr=0x%llx slide=0x%llx path=%s\n", i == 0 ? "(main) " : "", b,
               (unsigned long long)(uintptr_t)_dyld_get_image_header(i), (unsigned long long)(uintptr_t)_dyld_get_image_vmaddr_slide(i), name);
    }
}

// ---------------------------------------------------------------- 1: stall watchdog and sampler

typedef struct {
    int ok;                        // registers were read
    int haveInfo;                  // thread_info succeeded
    int runState, cpu, suspendCount;
    uint64_t pc, lr, fp, sp;
    int n;
    uint64_t fr[kZ1MaxFrames];
} Z1Sample;

// Takes ONE sample of the main thread. thread_info BEFORE the suspend (run state / cpu usage tell "busy" from "blocked"; after a suspend the state reads as stopped).
static void Z1_TakeSample(Z1Sample *s) {
    memset(s, 0, sizeof *s);
    mach_port_t t = (mach_port_t)atomic_load(&gZ1MainThread);
    kern_return_t (*suspendFn)(thread_act_t) = gZ1Suspend;
    kern_return_t (*resumeFn)(thread_act_t) = gZ1Resume;
    kern_return_t (*stateFn)(thread_act_t, thread_state_flavor_t, thread_state_t, mach_msg_type_number_t *) = gZ1GetState;
    uint64_t lo = gZ1MainStackLo, hi = gZ1MainStackHi;
    if (t == MACH_PORT_NULL || !suspendFn || !resumeFn || !stateFn || hi == 0 || lo >= hi) return;

    thread_basic_info_data_t bi;
    mach_msg_type_number_t bc = THREAD_BASIC_INFO_COUNT;
    if (thread_info(t, THREAD_BASIC_INFO, (thread_info_t)&bi, &bc) == KERN_SUCCESS) {
        s->haveInfo = 1;
        s->runState = bi.run_state;
        s->cpu = bi.cpu_usage;
        s->suspendCount = bi.suspend_count;
    }

    arm_thread_state64_t st;
    mach_msg_type_number_t cnt = ARM_THREAD_STATE64_COUNT;
    // ---- main thread is suspended from here to thread_resume: NOTHING but thread_get_state, arithmetic and reads of the thread's own stack ----
    if (suspendFn(t) == KERN_SUCCESS) {
        if (stateFn(t, ARM_THREAD_STATE64, (thread_state_t)&st, &cnt) == KERN_SUCCESS) {
            s->ok = 1;
            s->pc = Z1_STRIP(arm_thread_state64_get_pc(st));
            s->lr = Z1_STRIP(arm_thread_state64_get_lr(st));
            s->fp = (uint64_t)arm_thread_state64_get_fp(st);
            s->sp = (uint64_t)arm_thread_state64_get_sp(st);
            uint64_t fp = s->fp;
            if (s->sp >= lo && s->sp < hi) {
                for (int i = 0; i < kZ1MaxFrames; i++) {
                    if (fp < s->sp || (fp & 15u) != 0 || fp < lo || fp > hi - 16) break;   // inside [sp, hi), 16 aligned, a whole frame record fits
                    const uint64_t *rec = (const uint64_t *)(uintptr_t)fp;
                    uint64_t next = rec[0];
                    uint64_t ret = Z1_STRIP(rec[1]);
                    if (ret == 0) break;
                    s->fr[s->n++] = ret;
                    if (next <= fp) break;                                                   // the chain must climb
                    fp = next;
                }
            }
        }
        (void)resumeFn(t);
    }
    // ---- resumed ----
}

static const char *Z1_RunStateName(int st) {
    switch (st) {
        case 1: return "RUNNING";
        case 2: return "STOPPED";
        case 3: return "WAITING";
        case 4: return "UNINTERRUPTIBLE";
        case 5: return "HALTED";
        default: return "?";
    }
}

// Raw line first (always cheap and lock free), symbolised line second (dladdr takes dyld locks: if the stalled main thread holds one, only that second line is lost).
static void Z1_WriteSample(const Z1Sample *s, uint64_t pingAgeMs) {
    char b[2048];
    size_t o = 0;
    Z1_Stamp(b, sizeof b, &o);
    Z1_Cat(b, sizeof b, &o, "stall begin: main queue did not answer for %llu ms; main thread run=%s cpu=%d/1000 suspendCount=%d ok=%d\n",
           (unsigned long long)pingAgeMs, s->haveInfo ? Z1_RunStateName(s->runState) : "?", s->haveInfo ? s->cpu : -1, s->haveInfo ? s->suspendCount : -1, s->ok);
    Z1_Cat(b, sizeof b, &o, "   pc=0x%llx lr=0x%llx sp=0x%llx fp=0x%llx\n   bt(%d):", (unsigned long long)s->pc, (unsigned long long)s->lr, (unsigned long long)s->sp, (unsigned long long)s->fp, s->n);
    for (int i = 0; i < s->n; i++) Z1_Cat(b, sizeof b, &o, " 0x%llx", (unsigned long long)s->fr[i]);
    Z1_Cat(b, sizeof b, &o, "\n");
    Z1_Append(gZ1StallPath, b, o, YES);
    if (!s->ok) return;

    char c[3600];
    size_t q = 0;
    Z1_Cat(c, sizeof c, &q, "   sym:");
    uint64_t all[kZ1MaxFrames + 2];
    int m = 0;
    all[m++] = s->pc;
    all[m++] = s->lr;
    for (int i = 0; i < s->n; i++) all[m++] = s->fr[i];
    for (int i = 0; i < m; i++) {
        Dl_info di;
        memset(&di, 0, sizeof di);
        if (all[i] != 0 && dladdr((const void *)(uintptr_t)all[i], &di) && di.dli_fname) {
            unsigned long long off = (unsigned long long)(all[i] - (uint64_t)(uintptr_t)di.dli_fbase);
            if (di.dli_sname) Z1_Cat(c, sizeof c, &q, " %s+0x%llx(%s+0x%llx)", Z1_BaseName(di.dli_fname), off, di.dli_sname, (unsigned long long)(all[i] - (uint64_t)(uintptr_t)di.dli_saddr));
            else Z1_Cat(c, sizeof c, &q, " %s+0x%llx", Z1_BaseName(di.dli_fname), off);
        } else {
            Z1_Cat(c, sizeof c, &q, " ?");
        }
    }
    Z1_Cat(c, sizeof c, &q, "\n");
    Z1_Append(gZ1StallPath, c, q, YES);
}

typedef struct { uint64_t t[64]; int head; int n; } Z1Ring;   // sliding one hour window, thread confined
static BOOL Z1_RingTake(Z1Ring *r, int cap, uint64_t now) {
    if (cap > 64) cap = 64;
    if (r->n >= cap) {
        if (now - r->t[r->head] < Z1_HOUR_NS) return NO;
        r->head = (r->head + 1) % cap;
        r->n--;
    }
    r->t[(r->head + r->n) % cap] = now;
    r->n++;
    return YES;
}

static void *Z1_WatchdogMain(void *arg) {
    (void)arg;
    pthread_setname_np("Backport162.stall");
    sleep(20);                                    // start-up grace: SpringBoard's own launch work is not a stall worth sampling
    Z1Ring samples = {{0}, 0, 0}, lines = {{0}, 0, 0};
    uint64_t stallPing = 0;
    BOOL inStall = NO, stallLogged = NO;
    for (;;) {
        usleep(kZ1PollUs);
        if (!Z1_Enabled()) continue;
        uint64_t now = Z1_Now();
        uint64_t ping = atomic_load(&gZ1PingAt);
        if (ping == 0) {
            if (inStall) {
                uint64_t pong = atomic_load(&gZ1PongAt);
                uint64_t ms = pong > stallPing ? (pong - stallPing) / 1000000ull : 0;
                atomic_store(&gZ1LastStallMs, ms);
                atomic_store(&gZ1LastStallEndNs, pong);
                atomic_store(&gZ1InStall, 0);
                if (stallLogged) Z1_StallLine("stall ended after %llu ms", (unsigned long long)ms);
                inStall = NO;
            }
            atomic_store(&gZ1PingAt, now);
            dispatch_async(dispatch_get_main_queue(), ^{
                atomic_store(&gZ1PongAt, Z1_Now());
                atomic_store(&gZ1PingAt, 0);
            });
        } else if (!inStall && now > ping && now - ping > Z1_STALL_NS) {
            inStall = YES;
            stallPing = ping;
            atomic_store(&gZ1InStall, 1);
            atomic_fetch_add(&gZ1StallCount, 1);
            stallLogged = Z1_RingTake(&lines, kZ1LinesPerHr, now);
            if (stallLogged) {
                if (Z1_RingTake(&samples, kZ1SamplesPerHr, now)) {
                    Z1Sample s;
                    Z1_TakeSample(&s);
                    Z1_WriteSample(&s, (Z1_Now() - ping) / 1000000ull);
                } else {
                    Z1_StallLine("stall begin: main queue did not answer for %llu ms (no sample: %d per hour used)", (unsigned long long)((now - ping) / 1000000ull), (int)kZ1SamplesPerHr);
                }
            }
        }
    }
    return NULL;
}

static void Z1_CaptureMainThread(void) {
    pthread_t me = pthread_self();
    uint64_t hi = (uint64_t)(uintptr_t)pthread_get_stackaddr_np(me);       // highest address of the stack
    uint64_t size = (uint64_t)pthread_get_stacksize_np(me);
    gZ1MainStackHi = hi;
    gZ1MainStackLo = (hi > size) ? hi - size : 0;
    mach_port_t port = mach_thread_self();                                  // one send right, kept for the life of the process
    atomic_store(&gZ1MainThread, (uint32_t)port);
}

static void Z1_StartWatchdog(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gZ1Suspend = (kern_return_t (*)(thread_act_t))dlsym(RTLD_DEFAULT, "thread_suspend");
        gZ1Resume = (kern_return_t (*)(thread_act_t))dlsym(RTLD_DEFAULT, "thread_resume");
        gZ1GetState = (kern_return_t (*)(thread_act_t, thread_state_flavor_t, thread_state_t, mach_msg_type_number_t *))dlsym(RTLD_DEFAULT, "thread_get_state");
        pthread_attr_t attr;
        if (pthread_attr_init(&attr) != 0) return;
        pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
        pthread_attr_setstacksize(&attr, 512 * 1024);
        pthread_attr_set_qos_class_np(&attr, QOS_CLASS_USER_INITIATED, 0);
        pthread_t th;
        int rc = pthread_create(&th, &attr, Z1_WatchdogMain, NULL);
        pthread_attr_destroy(&attr);
        Z1_StallLine("watchdog %s (period %d ms, stall > %llu ms, sampler %s)", rc == 0 ? "started" : "NOT started", kZ1PollUs / 1000, Z1_STALL_NS / 1000000ull,
                     (gZ1Suspend && gZ1Resume && gZ1GetState) ? "ready" : "unavailable (dlsym)");
    });
}

// ---------------------------------------------------------------- 2: touch latency probe

static void Z1_StallStateText(char *b, size_t cap, size_t *o, uint64_t now) {
    uint64_t ping = atomic_load(&gZ1PingAt);
    uint64_t last = atomic_load(&gZ1LastStallMs), endNs = atomic_load(&gZ1LastStallEndNs), total = atomic_load(&gZ1StallCount);
    Z1_Cat(b, cap, o, "mainStall(inStall=%d", atomic_load(&gZ1InStall));
    if (ping != 0 && now > ping) Z1_Cat(b, cap, o, " pingAge=%llums", (unsigned long long)((now - ping) / 1000000ull));
    else Z1_Cat(b, cap, o, " pingAge=0");
    if (total != 0) Z1_Cat(b, cap, o, " last=%llums endedAgo=%llums total=%llu)", (unsigned long long)last, (unsigned long long)(endNs && now > endNs ? (now - endNs) / 1000000ull : 0), (unsigned long long)total);
    else Z1_Cat(b, cap, o, " stalls=0)");
}

static const char *Z1_PhaseName(long ph) {
    switch (ph) {
        case 0: return "began";
        case 1: return "moved";
        case 2: return "stationary";
        case 3: return "ended";
        case 4: return "cancelled";
        default: return "other";
    }
}

// Main thread only. Cost for an ordinary event: type test + two clock reads.
static void Z1_TouchProbe(UIEvent *event) {
    @try {
        static uint64_t lastLogNs;
        static unsigned suppressed;
        static BOOL firstDone;
        if (!event || !Z1_Enabled()) return;
        if (event.type != UIEventTypeTouches) return;
        NSTimeInterval ts = event.timestamp;
        uint64_t nowNs = Z1_Now();
        double lat = (double)nowNs / 1e9 - ts;
        if (!firstDone) {                                       // one line that proves the event clock and this hook (an off by hours latency would mean another clock base)
            firstDone = YES;
            Z1_StallLine("touchlat first touch event seen: latency %.1f ms (timestamp %.3f, now %.3f; the two must be on one clock)", lat * 1000.0, ts, (double)nowNs / 1e9);
        }
        if (!(ts > 0.0) || lat <= Z1_TOUCH_SEC || lat > 86400.0) return;
        atomic_fetch_add(&gZ1TouchLatCount, 1);
        if (lastLogNs != 0 && nowNs - lastLogNs < 1000000000ull) { suppressed++; return; }
        lastLogNs = nowNs;
        UITouch *pick = nil;
        NSUInteger count = 0;
        for (UITouch *t in [event allTouches]) {
            count++;
            if (!pick) pick = t;
            if (t.phase == UITouchPhaseBegan) pick = t;
        }
        UIWindow *w = pick ? pick.window : nil;
        CGPoint p = (pick && w) ? [pick locationInView:w] : CGPointZero;
        char b[900];
        size_t o = 0;
        Z1_Stamp(b, sizeof b, &o);
        Z1_Cat(b, sizeof b, &o, "touchlat %.0f ms phase=%s window=%s loc=(%.0f,%.0f) touches=%llu suppressed=%u ", lat * 1000.0, pick ? Z1_PhaseName((long)pick.phase) : "none",
               w ? object_getClassName(w) : "-", (double)p.x, (double)p.y, (unsigned long long)count, suppressed);
        Z1_StallStateText(b, sizeof b, &o, nowNs);
        Z1_Cat(b, sizeof b, &o, "\n");
        suppressed = 0;
        Z1_Append(gZ1StallPath, b, o, YES);
    } @catch (NSException *e) {
    }
}

%group Z1Touch
%hook SpringBoard
- (void)sendEvent:(UIEvent *)event {
    Z1_TouchProbe(event);
    %orig;
}
%end
%end

// ---------------------------------------------------------------- ObjC reflection helpers (every access guarded; main queue only)

static id Z1_Obj(id o, const char *sel) {
    if (!o) return nil;
    SEL s = sel_registerName(sel);
    if (![o respondsToSelector:s]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(o, s);
}
static long long Z1_Int(id o, const char *sel, long long dflt) {      // only for methods that return NSInteger / NSUInteger
    if (!o) return dflt;
    SEL s = sel_registerName(sel);
    if (![o respondsToSelector:s]) return dflt;
    return ((long long (*)(id, SEL))objc_msgSend)(o, s);
}
static int Z1_Bool(id o, const char *sel) {                           // -1 = absent
    if (!o) return -1;
    SEL s = sel_registerName(sel);
    if (![o respondsToSelector:s]) return -1;
    return ((BOOL (*)(id, SEL))objc_msgSend)(o, s) ? 1 : 0;
}
static int Z1_BoolArg(id o, const char *sel, unsigned long long arg) {
    if (!o) return -1;
    SEL s = sel_registerName(sel);
    if (![o respondsToSelector:s]) return -1;
    return ((BOOL (*)(id, SEL, unsigned long long))objc_msgSend)(o, s, arg) ? 1 : 0;
}
static id Z1_ObjIvar(id o, const char *name) {
    if (!o) return nil;
    Ivar iv = class_getInstanceVariable(object_getClass(o), name);
    return BP_ObjIvar(o, iv);                                          // nil unless the ivar exists AND is an object
}
static long long Z1_Count(id o) {                                      // collection size, -1 = absent / not a collection
    if (!o) return -1;
    SEL s = sel_registerName("count");
    if (![o respondsToSelector:s]) return -1;
    return (long long)((NSUInteger (*)(id, SEL))objc_msgSend)(o, s);
}
static NSString *Z1_N(long long n) { return n < 0 ? @"-" : [NSString stringWithFormat:@"%lld", n]; }
static NSString *Z1_CountIvar(id o, const char *name) { return Z1_N(Z1_Count(Z1_ObjIvar(o, name))); }
static NSString *Z1_Cls(id o) { return o ? NSStringFromClass([o class]) : @"nil"; }
static NSString *Z1_Short(id o, NSUInteger max) {
    if (!o) return @"nil";
    NSString *d = nil;
    @try { d = [o description]; } @catch (NSException *e) { d = nil; }
    if (![d isKindOfClass:[NSString class]]) return @"?";
    d = [d stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    return d.length > max ? [[d substringToIndex:max] stringByAppendingString:@"..."] : d;
}
static NSString *Z1_StateName(long long s) {
    switch (s) {
        case 0: return @"possible";
        case 1: return @"began";
        case 2: return @"changed";
        case 3: return @"ended";
        case 4: return @"cancelled";
        case 5: return @"failed";
        default: return [NSString stringWithFormat:@"%lld", s];
    }
}
static NSString *Z1_RecLine(id r) {
    id view = Z1_Obj(r, "view");
    return [NSString stringWithFormat:@"%@<%p> name=%@ state=%@ enabled=%d touches=%lld view=%@ viewHidden=%d delegate=%@", Z1_Cls(r), (__bridge void *)r, Z1_Short(Z1_Obj(r, "name"), 60),
            Z1_StateName(Z1_Int(r, "state", -1)), Z1_Bool(r, "isEnabled"), Z1_Int(r, "numberOfTouches", -1), Z1_Cls(view), Z1_Bool(view, "isHidden"), Z1_Cls(Z1_Obj(r, "delegate"))];
}
static NSArray *Z1_Array(id a) { return [a isKindOfClass:[NSArray class]] ? (NSArray *)a : nil; }
static UIApplication *Z1_App(void) {
    Class c = NSClassFromString(@"UIApplication");
    return (c && [c respondsToSelector:@selector(sharedApplication)]) ? [c sharedApplication] : nil;
}
static NSArray *Z1_Scenes(void) {
    UIApplication *app = Z1_App();
    id set = Z1_Obj(app, "connectedScenes");
    NSMutableArray *r = [NSMutableArray array];
    if ([set isKindOfClass:[NSSet class]]) for (id s in (NSSet *)set) { if (r.count < 8) [r addObject:s]; }
    return r;
}
static id Z1_GestureEnv(void) {
    UIApplication *app = Z1_App();
    id env = Z1_ObjIvar(app, "__gestureEnvironment");
    return env ? env : Z1_Obj(app, "_gestureEnvironment");
}

// ---------------------------------------------------------------- 3: vitals

static NSString *Z1_Fds(void) {
    typedef int (*ProcPidInfo)(int, int, uint64_t, void *, int);
    typedef struct { int32_t fd; uint32_t type; } FdInfo;               // struct proc_fdinfo
    ProcPidInfo fn = (ProcPidInfo)dlsym(RTLD_DEFAULT, "proc_pidinfo");
    if (fn) {
        int sz = fn(getpid(), 1 /* PROC_PIDLISTFDS */, 0, NULL, 0);
        if (sz > 0 && sz < 4 * 1024 * 1024) {
            sz += 16 * (int)sizeof(FdInfo);
            FdInfo *buf = (FdInfo *)calloc(1, (size_t)sz);
            if (buf) {
                int used = fn(getpid(), 1, 0, buf, sz);
                int n = used > 0 ? used / (int)sizeof(FdInfo) : 0, vn = 0, so = 0, kq = 0, pp = 0, ot = 0;
                for (int i = 0; i < n; i++) {
                    switch (buf[i].type) { case 1: vn++; break; case 2: so++; break; case 5: kq++; break; case 6: pp++; break; default: ot++; break; }
                }
                free(buf);
                return [NSString stringWithFormat:@"%d(vn=%d so=%d kq=%d pipe=%d oth=%d)", n, vn, so, kq, pp, ot];
            }
        }
    }
    int lim = getdtablesize(), n = 0;                                    // fallback: probe the descriptor table, bounded
    if (lim > 4096) lim = 4096;
    for (int i = 0; i < lim; i++) if (fcntl(i, F_GETFD) != -1) n++;
    return [NSString stringWithFormat:@"%d(probe<=%d)", n, lim];
}

static NSString *Z1_Ports(void) {
    mach_port_name_array_t names = NULL;
    mach_port_type_array_t types = NULL;
    mach_msg_type_number_t nc = 0, tc = 0;
    if (mach_port_names(mach_task_self(), &names, &nc, &types, &tc) != KERN_SUCCESS) return @"?";
    unsigned recv = 0, dead = 0;
    for (mach_msg_type_number_t i = 0; i < tc && i < nc; i++) {
        if (types[i] & MACH_PORT_TYPE_RECEIVE) recv++;
        else if (types[i] & MACH_PORT_TYPE_DEAD_NAME) dead++;
    }
    NSString *r = [NSString stringWithFormat:@"%u(recv=%u dead=%u)", (unsigned)nc, recv, dead];
    if (names) vm_deallocate(mach_task_self(), (vm_address_t)names, (vm_size_t)nc * sizeof(*names));
    if (types) vm_deallocate(mach_task_self(), (vm_address_t)types, (vm_size_t)tc * sizeof(*types));
    return r;
}

static int Z1_ThreadCount(void) {
    thread_act_array_t list = NULL;
    mach_msg_type_number_t n = 0;
    if (task_threads(mach_task_self(), &list, &n) != KERN_SUCCESS) return -1;
    for (mach_msg_type_number_t i = 0; i < n; i++) mach_port_deallocate(mach_task_self(), list[i]);
    if (list) vm_deallocate(mach_task_self(), (vm_address_t)list, (vm_size_t)n * sizeof(thread_t));
    return (int)n;
}

// The vitals text (without time stamp). Main queue only: it reads UIKit / SpringBoard objects.
static NSString *Z1_VitalsString(void) {
    NSMutableString *s = [NSMutableString string];
    uint64_t mono = clock_gettime_nsec_np(CLOCK_MONOTONIC), awake = Z1_Now();
    long long up = mono > gZ1StartMono ? (long long)((mono - gZ1StartMono) / 1000000000ull) : 0;
    long long aw = awake > gZ1StartAwake ? (long long)((awake - gZ1StartAwake) / 1000000000ull) : 0;
    struct timeval bt;
    size_t bl = sizeof bt;
    long long boot = -1;
    if (sysctlbyname("kern.boottime", &bt, &bl, NULL, 0) == 0) { struct timeval nw; gettimeofday(&nw, NULL); boot = (long long)(nw.tv_sec - bt.tv_sec); }
    [s appendFormat:@"vitals up=%lld s(%lldh%02lldm) awake=%lld s boot=%lld s", up, up / 3600, (up / 60) % 60, aw, boot];
    task_vm_info_data_t vm;
    mach_msg_type_number_t vc = TASK_VM_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&vm, &vc) == KERN_SUCCESS) [s appendFormat:@" footprint=%.1fMB", (double)vm.phys_footprint / 1048576.0];
    [s appendFormat:@" thr=%d fds=%@ ports=%@", Z1_ThreadCount(), Z1_Fds(), Z1_Ports()];
    @try {
        NSArray *scenes = Z1_Scenes();
        int wins = 0;
        NSMutableString *recs = [NSMutableString string];
        int listed = 0;
        for (id sc in scenes) {
            NSArray *ws = Z1_Array(Z1_Obj(sc, "windows"));
            for (id w in ws) {
                wins++;
                long long n = Z1_Count(Z1_Obj(w, "gestureRecognizers"));
                if (n > 0 && listed < 8) { [recs appendFormat:@"%@%@:%lld", listed ? @"," : @"", Z1_Cls(w), n]; listed++; }
            }
        }
        [s appendFormat:@" scenes=%lu uiwin=%d winrecs=[%@]", (unsigned long)scenes.count, wins, recs];
        for (id sc in scenes) {
            id mgr = Z1_Obj(sc, "systemGestureManager");
            if (!mgr) continue;
            int isMain = Z1_Bool(sc, "isMainDisplayWindowScene");
            id sgw = Z1_Obj(mgr, "windowForSystemGestures");
            [s appendFormat:@" | sgm[%@] sgwRecs=%@ recognizing=%@ touchGestures=%@ disableAsserts=%@ typeToGesture=%@ typeToState=%@", isMain == 1 ? @"main" : @"other", Z1_N(Z1_Count(Z1_Obj(sgw, "gestureRecognizers"))),
             Z1_CountIvar(mgr, "_recognizingTouchGestures"), Z1_CountIvar(mgr, "_touchGestures"), Z1_CountIvar(mgr, "_gesturesDisabledAssertions"), Z1_CountIvar(mgr, "_typeToGesture"), Z1_CountIvar(mgr, "_typeToState")];
        }
        id env = Z1_GestureEnv();
        if (env) {
            [s appendFormat:@" | uigenv blockedFromReset=%@ delayedTouches=%@ delayedTouchesToSend=%@ delayedPresses=%@ needUpdate=%@ needReset=%@ needRemoval=%@ dirty=%@ preUpdate=%@ nodes=%@",
             Z1_CountIvar(env, "_gestureRecognizersBlockedFromReset"), Z1_CountIvar(env, "_delayedTouches"), Z1_CountIvar(env, "_delayedTouchesToSend"), Z1_CountIvar(env, "_delayedPresses"),
             Z1_CountIvar(env, "_gestureRecognizersNeedingUpdate"), Z1_CountIvar(env, "_gestureRecognizersNeedingReset"), Z1_CountIvar(env, "_gestureRecognizersNeedingRemoval"),
             Z1_CountIvar(env, "_dirtyGestureRecognizers"), Z1_CountIvar(env, "_preUpdateActions"), Z1_CountIvar(env, "_nodesByGestureRecognizer")];
        } else {
            [s appendString:@" | uigenv absent"];
        }
    } @catch (NSException *e) {
        [s appendFormat:@" (ui part aborted: %@)", e.name];
    }
    [s appendFormat:@" | stalls=%llu touchlat=%llu", (unsigned long long)atomic_load(&gZ1StallCount), (unsigned long long)atomic_load(&gZ1TouchLatCount)];
    return s;
}

static void Z1_VitalsTick(void) {
    if (!Z1_Enabled()) return;
    @autoreleasepool {
        @try {
            char b[4096];
            size_t o = 0;
            Z1_Stamp(b, sizeof b, &o);
            const char *u = Z1_VitalsString().UTF8String;
            Z1_Cat(b, sizeof b, &o, "%s", u ? u : "vitals ?");
            if (o + 2 > sizeof b) o = sizeof b - 2;                 // a truncated line still ends with a newline
            b[o++] = '\n';
            Z1_Append(gZ1VitalsPath, b, o, NO);
        } @catch (NSException *e) {
        }
    }
}

// ---------------------------------------------------------------- 4: state dump

static void Z1_Put(NSMutableString *o, NSString *fmt, ...) NS_FORMAT_FUNCTION(2, 3);
static void Z1_Put(NSMutableString *o, NSString *fmt, ...) {
    if (o.length > 800000) return;
    va_list ap;
    va_start(ap, fmt);
    NSString *s = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    [o appendString:s];
}

static void Z1_Guard(NSMutableString *o, NSString *what, void (^body)(void)) {
    @try { body(); }
    @catch (NSException *e) { Z1_Put(o, @"(section %@ aborted: %@ %@)\n", what, e.name, Z1_Short(e.reason, 200)); }
}

static void Z1_DumpRecList(NSMutableString *o, NSString *indent, id coll, NSUInteger max, id env) {
    NSUInteger i = 0;
    id src = coll;
    if ([coll isKindOfClass:[NSSet class]]) src = [(NSSet *)coll allObjects];
    if (![src isKindOfClass:[NSArray class]]) return;
    for (id r in (NSArray *)src) {
        if (i++ >= max) { Z1_Put(o, @"%@... (%lu more)\n", indent, (unsigned long)([(NSArray *)src count] - max)); break; }
        id renv = Z1_ObjIvar(r, "_gestureEnvironment");
        Z1_Put(o, @"%@%@ env=%@\n", indent, Z1_RecLine(r), (env && renv) ? (renv == env ? @"same" : @"DIFFERENT") : @"?");
    }
}

static void Z1_DumpManager(NSMutableString *o, id mgr, id env) {
    Z1_Put(o, @"  systemGestureManager %@<%p> displayIdentity=%@\n", Z1_Cls(mgr), (__bridge void *)mgr, Z1_Short(Z1_ObjIvar(mgr, "_displayIdentity"), 120));
    id sgw = Z1_Obj(mgr, "windowForSystemGestures");
    Z1_Put(o, @"  windowForSystemGestures %@<%p> hidden=%d level=%@ gestureRecognizers=%@\n", Z1_Cls(sgw), (__bridge void *)sgw, Z1_Bool(sgw, "isHidden"), Z1_N([sgw isKindOfClass:[UIWindow class]] ? (long long)((UIWindow *)sgw).windowLevel : -1),
           Z1_N(Z1_Count(Z1_Obj(sgw, "gestureRecognizers"))));
    Z1_DumpRecList(o, @"    window rec: ", Z1_Obj(sgw, "gestureRecognizers"), 24, env);
    id t2g = Z1_ObjIvar(mgr, "_typeToGesture"), t2s = Z1_ObjIvar(mgr, "_typeToState");
    Z1_Put(o, @"  _typeToGesture (%@ entries), type -> recognizer ; _typeToState value:\n", Z1_N(Z1_Count(t2g)));
    if ([t2g isKindOfClass:[NSDictionary class]]) {
        NSArray *keys = [[(NSDictionary *)t2g allKeys] sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
            if ([a isKindOfClass:[NSNumber class]] && [b isKindOfClass:[NSNumber class]]) return [(NSNumber *)a compare:(NSNumber *)b];
            return NSOrderedSame;
        }];
        NSUInteger i = 0;
        for (id k in keys) {
            if (i++ >= 80) { Z1_Put(o, @"    ...\n"); break; }
            id r = [(NSDictionary *)t2g objectForKey:k];
            id st = [t2s isKindOfClass:[NSDictionary class]] ? [(NSDictionary *)t2s objectForKey:k] : nil;
            NSString *ks = [k isKindOfClass:[NSNumber class]] ? [NSString stringWithFormat:@"0x%llx", [(NSNumber *)k unsignedLongLongValue]] : Z1_Short(k, 40);
            id renv = Z1_ObjIvar(r, "_gestureEnvironment");
            Z1_Put(o, @"    %@ -> %@ env=%@ ; typeToState=%@\n", ks, Z1_RecLine(r), (env && renv) ? (renv == env ? @"same" : @"DIFFERENT") : @"?", Z1_Short(st, 60));
        }
    }
    id rec = Z1_ObjIvar(mgr, "_recognizingTouchGestures");
    Z1_Put(o, @"  _recognizingTouchGestures (%@):\n", Z1_N(Z1_Count(rec)));
    Z1_DumpRecList(o, @"    ", rec, 24, env);
    Z1_Put(o, @"  _touchGestures=%@ _gestureToType=%@\n", Z1_CountIvar(mgr, "_touchGestures"), Z1_CountIvar(mgr, "_gestureToType"));
    id dis = Z1_ObjIvar(mgr, "_gesturesDisabledAssertions");
    Z1_Put(o, @"  _gesturesDisabledAssertions (%@):\n", Z1_N(Z1_Count(dis)));
    if ([dis isKindOfClass:[NSSet class]]) {
        NSUInteger i = 0;
        for (id a in (NSSet *)dis) {
            if (i++ >= 40) { Z1_Put(o, @"    ...\n"); break; }
            Z1_Put(o, @"    %@<%p> %@\n", Z1_Cls(a), (__bridge void *)a, Z1_Short(a, 240));
        }
    }
    Z1_Put(o, @"  _gestureTypesAllowedWhileDisableAssertionsExist=%@\n", Z1_Short(Z1_ObjIvar(mgr, "_gestureTypesAllowedWhileDisableAssertionsExist"), 300));
    Z1_Put(o, @"  _gesturesPreventedByStylus=%@\n", Z1_Short(Z1_ObjIvar(mgr, "_gesturesPreventedByStylus"), 300));
    static const unsigned long long kTypes[] = {0x13, 0x16, 0x22, 0x2b};
    for (size_t i = 0; i < sizeof kTypes / sizeof kTypes[0]; i++) Z1_Put(o, @"  isGestureWithTypeAllowed:0x%llx = %d\n", kTypes[i], Z1_BoolArg(mgr, "isGestureWithTypeAllowed:", kTypes[i]));
    Z1_Put(o, @"  isAnyTouchGestureRunning=%d areSystemGesturesDisabledForAccessibility=%d\n", Z1_Bool(mgr, "isAnyTouchGestureRunning"), Z1_Bool(mgr, "areSystemGesturesDisabledForAccessibility"));
    static const char *const kTokens[] = {"_stylusPriorityRecognizer", "_systemGestureEventDeferringRule", "_pointerEventRoutingAssertion", "_systemGesturesAllowedToken", "_systemPointerContextIDAssertion", "_indirectTouchLifecycleMonitor"};
    for (size_t i = 0; i < sizeof kTokens / sizeof kTokens[0]; i++) {
        id v = Z1_ObjIvar(mgr, kTokens[i]);
        Z1_Put(o, @"  %s = %@\n", kTokens[i], v ? [NSString stringWithFormat:@"%@<%p>", Z1_Cls(v), (__bridge void *)v] : @"nil");
    }
}

static void Z1_DumpEnv(NSMutableString *o, id env) {
    Z1_Put(o, @"UIGestureEnvironment (UIApplication._gestureEnvironment) %@<%p>\n", Z1_Cls(env), (__bridge void *)env);
    if (!env) { Z1_Put(o, @"  absent\n"); return; }
    static const char *const kNames[] = {"_gestureRecognizersNeedingUpdate", "_gestureRecognizersNeedingReset", "_gestureRecognizersNeedingRemoval", "_dirtyGestureRecognizers", "_gestureRecognizersBlockedFromReset",
                                         "_delayedTouches", "_delayedTouchesToSend", "_delayedPresses", "_delayedPressesToSend", "_preUpdateActions", "_nodesByGestureRecognizer"};
    for (size_t i = 0; i < sizeof kNames / sizeof kNames[0]; i++) Z1_Put(o, @"  %s count = %@\n", kNames[i], Z1_CountIvar(env, kNames[i]));
    @try {
        id v = [env valueForKey:@"_lastBlockedResetEvaluationMachTime"];
        unsigned long long mt = [v isKindOfClass:[NSNumber class]] ? [(NSNumber *)v unsignedLongLongValue] : 0;
        mach_timebase_info_data_t tb;
        mach_timebase_info(&tb);
        double ageS = (mt && tb.denom) ? (double)((mach_absolute_time() - mt) * tb.numer / tb.denom) / 1e9 : -1.0;
        Z1_Put(o, @"  _lastBlockedResetEvaluationMachTime = %llu (%.1f s ago; -1 = never)\n", mt, ageS);
        Z1_Put(o, @"  _isUpdatingGestureEnvironment = %@ _updateExclusivity = %@ _dirtyGestureRecognizersUnsorted = %@\n", Z1_Short([env valueForKey:@"_isUpdatingGestureEnvironment"], 20),
               Z1_Short([env valueForKey:@"_updateExclusivity"], 20), Z1_Short([env valueForKey:@"_dirtyGestureRecognizersUnsorted"], 20));
    } @catch (NSException *e) {
        Z1_Put(o, @"  (scalar ivars unavailable: %@)\n", e.name);
    }
    Z1_Put(o, @"  _blockedResetStateCaptureToken = %@\n", Z1_Cls(Z1_ObjIvar(env, "_blockedResetStateCaptureToken")));
    Z1_Put(o, @"  _gestureRecognizersBlockedFromReset members (a recognizer that never resets delays later touches):\n");
    Z1_DumpRecList(o, @"    ", Z1_ObjIvar(env, "_gestureRecognizersBlockedFromReset"), 30, env);
    for (NSString *n in @[@"_delayedTouches", @"_delayedTouchesToSend"]) {
        id arr = Z1_ObjIvar(env, n.UTF8String);
        Z1_Put(o, @"  %@ first entries:\n", n);
        NSUInteger i = 0;
        for (id e in (Z1_Array(arr) ?: @[])) {
            if (i++ >= 5) break;
            Z1_Put(o, @"    %@\n", Z1_Short(e, 220));
        }
    }
}

static void Z1_DumpTransaction(NSMutableString *o, id tx, int depth, int *budget) {
    if (!tx || depth > 8 || *budget <= 0) return;
    (*budget)--;
    NSMutableString *ind = [NSMutableString string];
    for (int i = 0; i < depth; i++) [ind appendString:@"  "];
    id start = Z1_ObjIvar(tx, "_startTime");
    double age = [start respondsToSelector:@selector(timeIntervalSinceNow)] ? -[(NSDate *)start timeIntervalSinceNow] : -1.0;
    Z1_Put(o, @"  %@%@<%p> started=%d running=%d complete=%d finishedWorking=%d interrupted=%d failed=%d age=%.1fs\n", ind, Z1_Cls(tx), (__bridge void *)tx, Z1_Bool(tx, "hasStarted"), Z1_Bool(tx, "isRunning"),
           Z1_Bool(tx, "isComplete"), Z1_Bool(tx, "isFinishedWorking"), Z1_Bool(tx, "isInterrupted"), Z1_Bool(tx, "isFailed"), age);
    for (id c in (Z1_Array(Z1_Obj(tx, "childTransactions")) ?: @[])) Z1_DumpTransaction(o, c, depth + 1, budget);
}

static void Z1_DumpAssertion(NSMutableString *o, id owner, const char *ivar) {
    id a = Z1_ObjIvar(owner, ivar);
    if (!a) { Z1_Put(o, @"  %s = nil\n", ivar); return; }
    Z1_Put(o, @"  %s = %@<%p> active=%d\n", ivar, Z1_Cls(a), (__bridge void *)a, Z1_Bool(a, "isActive"));
    id reasons = Z1_Obj(a, "reasons");
    if ([reasons isKindOfClass:[NSSet class]]) {
        NSUInteger i = 0;
        for (id r in (NSSet *)reasons) {
            if (i++ >= 30) { Z1_Put(o, @"      ...\n"); break; }
            Z1_Put(o, @"      reason: %@\n", Z1_Short(r, 200));
        }
    }
}

static void Z1_DumpBody(NSMutableString *o) {
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    char osv[40] = {0};
    size_t n = sizeof osv - 1;
    if (sysctlbyname("kern.osversion", osv, &n, NULL, 0) != 0) snprintf(osv, sizeof osv, "?");
    Z1_Put(o, @"Backport162 state dump  pid=%d os=%s  unix time=%lld\n", (int)getpid(), osv, (long long)ts.tv_sec);
    Z1_Put(o, @"%@\n", Z1_VitalsString());
    char sb[256];
    size_t so = 0;
    Z1_StallStateText(sb, sizeof sb, &so, Z1_Now());
    Z1_Put(o, @"%s\n\n", sb);

    id env = Z1_GestureEnv();
    int idx = 0;
    for (id sc in Z1_Scenes()) {
        int i = idx++;
        Z1_Guard(o, [NSString stringWithFormat:@"scene%d", i], ^{
            Z1_Put(o, @"=== window scene [%d] %@<%p> main=%d external=%d activationState=%lld session=%@\n", i, Z1_Cls(sc), (__bridge void *)sc, Z1_Bool(sc, "isMainDisplayWindowScene"), Z1_Bool(sc, "isExternalDisplayWindowScene"),
                   Z1_Int(sc, "activationState", -9), Z1_Short(Z1_Obj(Z1_Obj(sc, "session"), "persistentIdentifier"), 80));
            NSArray *ws = Z1_Array(Z1_Obj(sc, "windows"));
            Z1_Put(o, @"windows (%lu):\n", (unsigned long)ws.count);
            for (id w in ws) {
                Z1_Put(o, @"  %@<%p> hidden=%d alpha=%.2f userInteraction=%d gestureRecognizers=%@\n", Z1_Cls(w), (__bridge void *)w, Z1_Bool(w, "isHidden"), (double)[(UIWindow *)w alpha], Z1_Bool(w, "isUserInteractionEnabled"),
                       Z1_N(Z1_Count(Z1_Obj(w, "gestureRecognizers"))));
                NSString *cn = Z1_Cls(w);
                if ([cn rangeOfString:@"CoverSheet"].location != NSNotFound || [cn rangeOfString:@"SystemGesture"].location != NSNotFound)
                    Z1_DumpRecList(o, @"      rec: ", Z1_Obj(w, "gestureRecognizers"), 24, env);
            }
            id mgr = Z1_Obj(sc, "systemGestureManager");
            if (mgr) Z1_DumpManager(o, mgr, env);
            else Z1_Put(o, @"  (no systemGestureManager)\n");
            Z1_Put(o, @"\n");
        });
    }
    Z1_Guard(o, @"env", ^{ Z1_DumpEnv(o, env); Z1_Put(o, @"\n"); });
    Z1_Guard(o, @"workspace", ^{
        Class wc = NSClassFromString(@"SBMainWorkspace");
        id ws = nil;
        if ([wc respondsToSelector:NSSelectorFromString(@"sharedInstanceIfExists")]) ws = Z1_Obj((id)wc, "sharedInstanceIfExists");
        if (!ws && [wc respondsToSelector:NSSelectorFromString(@"sharedInstance")]) ws = Z1_Obj((id)wc, "sharedInstance");
        Z1_Put(o, @"SBMainWorkspace %@<%p> current transaction chain:\n", Z1_Cls(ws), (__bridge void *)ws);
        int budget = 60;
        Z1_DumpTransaction(o, Z1_Obj(ws, "currentTransaction"), 0, &budget);
        Z1_DumpAssertion(o, ws, "_lockKeyboardFocusAssertion");
        id kfc = Z1_ObjIvar(ws, "_keyboardFocusController");
        Z1_Put(o, @"keyboard focus controller %@<%p> windowSceneWithFocus=%@ externalSceneWithFocus=%@ springBoardFocusLockWindowScene=%@\n", Z1_Cls(kfc), (__bridge void *)kfc,
               Z1_Cls(Z1_ObjIvar(kfc, "_windowSceneWithFocus")), Z1_Cls(Z1_ObjIvar(kfc, "_externalSceneWithFocus")), Z1_Cls(Z1_ObjIvar(kfc, "_springBoardFocusLockWindowScene")));
        static const char *const kA[] = {"_springBoardFocusLockAssertions", "_springBoardFocusRedirections", "_appFocusRedirections", "_springBoardWindowFocusStealingAssertions", "_preventFocusForSceneAssertion"};
        for (size_t i = 0; i < sizeof kA / sizeof kA[0]; i++) Z1_DumpAssertion(o, kfc, kA[i]);
        Z1_Put(o, @"\n");
    });
    Z1_Put(o, @"X7 counters: X7Keyboard.x exports none (not included).\nend of dump\n");
}

static void Z1_DumpState(void) {
    if (!Z1_Enabled()) return;
    @autoreleasepool {
        NSMutableString *o = [NSMutableString stringWithCapacity:32768];
        @try { Z1_DumpBody(o); }
        @catch (NSException *e) { Z1_Put(o, @"\n(dump aborted: %@ %@)\n", e.name, Z1_Short(e.reason, 200)); }
        @try {
            NSData *d = [o dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:YES];
            if (d.length > kZ1DumpCap) d = [d subdataWithRange:NSMakeRange(0, kZ1DumpCap)];
            int fd = open(gZ1StatePath, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
            if (fd >= 0) {
                const char *p = (const char *)d.bytes;
                size_t left = d.length;
                while (left > 0) {
                    ssize_t w = write(fd, p, left);
                    if (w <= 0) break;
                    p += w;
                    left -= (size_t)w;
                }
                close(fd);
            }
            Z1_StallLine("state dump written to %s (%llu bytes)", Z1_BaseName(gZ1StatePath), (unsigned long long)d.length);
        } @catch (NSException *e) {
        }
    }
}

// ---------------------------------------------------------------- setup

void Z1_Setup(void);
void Z1_Setup(void) {
    static BOOL done;
    if (done) return;
    done = YES;
    @try {
        NSString *tmp = ROOT_PATH_NS(@"/tmp");                      // the directory BP_Log writes to
        const char *t = tmp.fileSystemRepresentation;
        if (!t || !t[0]) return;
        snprintf(gZ1StallPath, sizeof gZ1StallPath, "%s/Backport162.stall.log", t);
        snprintf(gZ1VitalsPath, sizeof gZ1VitalsPath, "%s/Backport162.vitals.log", t);
        snprintf(gZ1StatePath, sizeof gZ1StatePath, "%s/Backport162.state.txt", t);
        gZ1StartMono = clock_gettime_nsec_np(CLOCK_MONOTONIC);
        gZ1StartAwake = Z1_Now();
        Z1_BuildHeader();
        Z1_Append(gZ1StallPath, gZ1Hdr, strlen(gZ1Hdr), NO);

        // 1: watchdog (needs the main thread's port: captured here when the %ctor runs on the main thread, else from the main queue)
        if (pthread_main_np()) {
            Z1_CaptureMainThread();
            Z1_StartWatchdog();
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                Z1_CaptureMainThread();
                Z1_StartWatchdog();
            });
        }

        // 2: touch latency probe (hook of SpringBoard sendEvent:, see the header comment)
        if (NSClassFromString(@"SpringBoard")) {
            %init(Z1Touch);
            Z1_StallLine("touchlat hook installed (SpringBoard sendEvent:, threshold %.0f ms, 1 line/s)", Z1_TOUCH_SEC * 1000.0);
        } else {
            Z1_StallLine("touchlat hook NOT installed (no SpringBoard class)");
        }

        // 3: vitals once a minute on the main queue (first line after 30 s)
        gZ1Timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        if (gZ1Timer) {
            dispatch_source_set_timer(gZ1Timer, dispatch_time(DISPATCH_TIME_NOW, 30ull * NSEC_PER_SEC), 60ull * NSEC_PER_SEC, 5ull * NSEC_PER_SEC);
            dispatch_source_set_event_handler(gZ1Timer, ^{ Z1_VitalsTick(); });
            dispatch_resume(gZ1Timer);
        }

        // 4: state dump on request
        uint32_t st = notify_register_dispatch("com.infernowolf19.backport162.dumpstate", &gZ1DumpToken, dispatch_get_main_queue(), ^(int token) { Z1_DumpState(); });
        if (st != NOTIFY_STATUS_OK) Z1_StallLine("cannot register for the dumpstate notification (status %u)", (unsigned)st);
        BP_Log(@"[z1] diag instruments installed (stall watchdog, touch probe, vitals, state dump)");
    } @catch (NSException *e) {
        BP_Log(@"[z1] setup failed: %@", e.name);
    }
}

#pragma clang diagnostic pop
