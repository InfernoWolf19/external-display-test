// BPCrash.m - built-in crash recorder.
// ReportCrash does not always write a SpringBoard .ips on a jailbroken device, so the tweak records its own crash report:
// <jbroot>/tmp/Backport162.crash (appended, trimmed at launch when larger than 256 KiB). It holds the signal, fault address, the
// registers x0-x8, and a frame-pointer backtrace as "image+0xOFFSET (symbol+off)". Offsets of Backport162.dylib can be resolved against
// the CI build of the same commit (llvm-objdump --arch=arm64e). Uncaught Objective-C exceptions are recorded with name, reason and stack.
#import <Foundation/Foundation.h>
#include <signal.h>
#include <sys/ucontext.h>
#include <dlfcn.h>
#include <unistd.h>
#include <fcntl.h>
#include <string.h>
#include <stdio.h>
#include <time.h>
#include <sys/stat.h>

#define BPC_MASK 0x0000007fffffffffULL
static char gBPCPath[512];
static char gBPCStack[96 * 1024];
static NSUncaughtExceptionHandler *gBPCPrevExc;

static void bpc_put(int fd, const char *s) { if (fd >= 0 && s) (void)!write(fd, s, strlen(s)); }

// Async-signal-safe number writers (snprintf / printf family may take locale locks or allocate; the handler runs on a crashed process).
static void bpc_hex(int fd, unsigned long long v) {
    char b[19]; int i = 18; b[i] = 0;
    do { unsigned d = (unsigned)(v & 0xf); b[--i] = (char)(d < 10 ? '0' + d : 'a' + d - 10); v >>= 4; } while (v && i > 2);
    b[--i] = 'x'; b[--i] = '0';
    bpc_put(fd, b + i);
}
static void bpc_dec(int fd, long long v) {
    char b[24]; int i = 23; b[i] = 0;
    unsigned long long u = v < 0 ? (unsigned long long)(-(v + 1)) + 1ULL : (unsigned long long)v;
    do { b[--i] = (char)('0' + u % 10); u /= 10; } while (u && i > 1);
    if (v < 0) b[--i] = '-';
    bpc_put(fd, b + i);
}

static void bpc_frame(int fd, int i, uintptr_t raw) {
    uintptr_t a = (uintptr_t)((unsigned long long)raw & BPC_MASK);
    Dl_info di;
    bpc_dec(fd, i); bpc_put(fd, " "); bpc_hex(fd, a);
    if (a && dladdr((void *)a, &di) && di.dli_fname) {
        const char *n = strrchr(di.dli_fname, '/'); n = n ? n + 1 : di.dli_fname;
        bpc_put(fd, " "); bpc_put(fd, n); bpc_put(fd, "+"); bpc_hex(fd, (unsigned long long)(a - (uintptr_t)di.dli_fbase));
        if (di.dli_sname) { bpc_put(fd, "  "); bpc_put(fd, di.dli_sname); bpc_put(fd, "+"); bpc_dec(fd, (long long)(a - (uintptr_t)di.dli_saddr)); }
        bpc_put(fd, "\n");
    } else bpc_put(fd, " ?\n");
}

static volatile sig_atomic_t gBPCInHandler;

static void bpc_handler(int sig, siginfo_t *si, void *ctx) {
    // A second fatal signal (another thread, or a fault inside this handler) must never run the recorder again: give up and let the default action take the process.
    if (gBPCInHandler) { signal(sig, SIG_DFL); return; }
    gBPCInHandler = 1;
    // dladdr takes dyld's lock; if the crashing thread (or another one) holds it the handler would hang SpringBoard until the 180 s checkin watchdog fires. SIGALRM's default
    // action terminates the process, which turns a would-be hang into an ordinary crash a couple of seconds later.
    signal(SIGALRM, SIG_DFL);
    alarm(3);
    int fd = open(gBPCPath, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd >= 0) {
        bpc_put(fd, "\n=== Backport162 crash: signal "); bpc_dec(fd, sig);
        bpc_put(fd, " code "); bpc_dec(fd, si ? si->si_code : 0);
        bpc_put(fd, " fault-address "); bpc_hex(fd, si ? (unsigned long long)(uintptr_t)si->si_addr : 0ULL);
        bpc_put(fd, " pid "); bpc_dec(fd, (long long)getpid());
        bpc_put(fd, " time "); bpc_dec(fd, (long long)time(NULL)); bpc_put(fd, "\n");
        ucontext_t *uc = (ucontext_t *)ctx;
        if (uc && uc->uc_mcontext) {
            _STRUCT_ARM_THREAD_STATE64 *ss = &uc->uc_mcontext->__ss;
            uintptr_t pc = (uintptr_t)__darwin_arm_thread_state64_get_pc(*ss);
            uintptr_t lr = (uintptr_t)__darwin_arm_thread_state64_get_lr(*ss);
            uintptr_t fp = (uintptr_t)__darwin_arm_thread_state64_get_fp(*ss);
            uintptr_t sp = (uintptr_t)__darwin_arm_thread_state64_get_sp(*ss);
            for (int r = 0; r < 9; r++) { bpc_put(fd, r ? " x" : "x"); bpc_dec(fd, r); bpc_put(fd, "="); bpc_hex(fd, (unsigned long long)ss->__x[r]); }
            bpc_put(fd, "\n");
            int i = 0;
            bpc_frame(fd, i++, pc);
            bpc_frame(fd, i++, lr);
            for (; i < 48; i++) {
                if (!fp || (fp & 7) || fp < sp || fp - sp > 0x800000) break;
                uintptr_t *f = (uintptr_t *)fp;
                uintptr_t ret = f[1], next = f[0];
                if (!ret) break;
                bpc_frame(fd, i, ret);
                if (next <= fp) break;
                fp = next;
            }
        }
        close(fd);
    }
    alarm(0);
    signal(sig, SIG_DFL);        // re-raised by returning (SA_RESETHAND): the normal crash reporting continues
    gBPCInHandler = 0;
}

static void bpc_exception(NSException *e) {
    int fd = open(gBPCPath, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd >= 0) {
        bpc_put(fd, "\n=== Backport162 uncaught exception\n");
        bpc_put(fd, e.name.UTF8String);
        bpc_put(fd, ": ");
        bpc_put(fd, e.reason.UTF8String);
        bpc_put(fd, "\n");
        for (NSString *s in e.callStackSymbols) { bpc_put(fd, s.UTF8String); bpc_put(fd, "\n"); }
        close(fd);
    }
    if (gBPCPrevExc) gBPCPrevExc(e);
}

void BP_InstallCrashRecorder(const char *tmpDir) {
    snprintf(gBPCPath, sizeof gBPCPath, "%s/Backport162.crash", tmpDir);
    struct stat st;
    if (stat(gBPCPath, &st) == 0 && st.st_size > 256 * 1024) unlink(gBPCPath);
    stack_t ss = { .ss_sp = gBPCStack, .ss_size = sizeof gBPCStack, .ss_flags = 0 };
    sigaltstack(&ss, NULL);
    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_sigaction = bpc_handler;
    sa.sa_flags = SA_SIGINFO | SA_ONSTACK | SA_RESETHAND;
    sigemptyset(&sa.sa_mask);
    int sigs[] = { SIGSEGV, SIGBUS, SIGABRT, SIGILL, SIGTRAP, SIGFPE };
    for (size_t i = 0; i < sizeof sigs / sizeof sigs[0]; i++) sigaction(sigs[i], &sa, NULL);
    gBPCPrevExc = NSGetUncaughtExceptionHandler();
    NSSetUncaughtExceptionHandler(bpc_exception);
}
