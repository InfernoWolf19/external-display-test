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

static void bpc_frame(int fd, int i, uintptr_t raw) {
    char b[640];
    uintptr_t a = (uintptr_t)((unsigned long long)raw & BPC_MASK);
    Dl_info di;
    if (a && dladdr((void *)a, &di) && di.dli_fname) {
        const char *n = strrchr(di.dli_fname, '/'); n = n ? n + 1 : di.dli_fname;
        if (di.dli_sname) snprintf(b, sizeof b, "%2d 0x%llx %s+0x%llx  %s+%llu\n", i, (unsigned long long)a, n, (unsigned long long)(a - (uintptr_t)di.dli_fbase), di.dli_sname, (unsigned long long)(a - (uintptr_t)di.dli_saddr));
        else snprintf(b, sizeof b, "%2d 0x%llx %s+0x%llx\n", i, (unsigned long long)a, n, (unsigned long long)(a - (uintptr_t)di.dli_fbase));
    } else snprintf(b, sizeof b, "%2d 0x%llx ?\n", i, (unsigned long long)a);
    bpc_put(fd, b);
}

static void bpc_handler(int sig, siginfo_t *si, void *ctx) {
    int fd = open(gBPCPath, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd >= 0) {
        char b[256];
        snprintf(b, sizeof b, "\n=== Backport162 crash: signal %d code %d fault-address 0x%llx pid %d time %lld\n", sig, si ? si->si_code : 0, si ? (unsigned long long)(uintptr_t)si->si_addr : 0ULL, (int)getpid(), (long long)time(NULL));
        bpc_put(fd, b);
        ucontext_t *uc = (ucontext_t *)ctx;
        if (uc && uc->uc_mcontext) {
            _STRUCT_ARM_THREAD_STATE64 *ss = &uc->uc_mcontext->__ss;
            uintptr_t pc = (uintptr_t)__darwin_arm_thread_state64_get_pc(*ss);
            uintptr_t lr = (uintptr_t)__darwin_arm_thread_state64_get_lr(*ss);
            uintptr_t fp = (uintptr_t)__darwin_arm_thread_state64_get_fp(*ss);
            uintptr_t sp = (uintptr_t)__darwin_arm_thread_state64_get_sp(*ss);
            snprintf(b, sizeof b, "x0=%llx x1=%llx x2=%llx x3=%llx x4=%llx x5=%llx x6=%llx x7=%llx x8=%llx\n",
                     (unsigned long long)ss->__x[0], (unsigned long long)ss->__x[1], (unsigned long long)ss->__x[2], (unsigned long long)ss->__x[3],
                     (unsigned long long)ss->__x[4], (unsigned long long)ss->__x[5], (unsigned long long)ss->__x[6], (unsigned long long)ss->__x[7], (unsigned long long)ss->__x[8]);
            bpc_put(fd, b);
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
    signal(sig, SIG_DFL);        // re-raised by returning (SA_RESETHAND), the normal crash reporting continues
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
