// BPGuard.c - Backport162 boot guard: the ONLY dylib that has the SpringBoard filter plist (Backport162.plist, installed as Backport162.dylib in
// MobileSubstrate/DynamicLibraries = TweakInject). The real tweak is Backport162Core.dylib, installed OUTSIDE the injector's directory without a
// filter plist, so nothing loads it except this file. Spec: specs/BOOTGUARD-0.7.9.md.
//
// Why: build 50bd5e8 hung SpringBoard at load time (a constructor created SpringBoard singletons while SpringBoard was loading its images), the iPad
// sat on the Apple logo and the only way out was booting stock and re-jailbreaking with tweak injection disabled. This file makes that impossible
// for everything inside the core: if a SpringBoard launch loaded the core and never reached "finished booting", the NEXT launch does not load it.
//
// This file is PURE C on libSystem only: no Objective-C, no CoreFoundation, no CydiaSubstrate, no libroot, no message to any SpringBoard object, nothing
// from the tweak. It must stay that way (CI fails the build when the loader links anything but /usr/lib and /System/Library, see the workflow).
//
// State (all under <jbroot>/tmp, the directory Tweak.x uses for its kill files):
//   Backport162.booting   marker: exists from the moment the core is about to be loaded until SpringBoard has really finished booting
//   Backport162.tripped   written when the guard skipped a launch (timestamp + the marker's content); informational, postinst / the user deletes it
//   Backport162.log       one line per trip (written even without Backport162.debug), one line when dlopen of the core fails
//   Backport162.noguard   escape hatch: the guard is off, the core is always loaded
//   Backport162.off.all   escape hatch: the core is never loaded
//   Backport162.debug     (existing) also makes the loader log what it decides
//
// Launch logic (bpg_launch):
//   off.all exists                -> core NOT loaded, stale marker removed
//   not SpringBoard (never so far) -> core loaded, no marker (the marker is a SpringBoard boot marker)
//   noguard exists                -> stale marker removed, core loaded, no marker
//   booting exists                -> TRIPPED: marker removed, tripped written, log line, core NOT loaded (this launch boots stock; the next one retries)
//   otherwise                     -> marker created, clear of the marker scheduled, core loaded
// The marker is cleared by a block on the MAIN QUEUE, 45 s after the main queue first ran a block (= the main run loop is up and turning), so a main thread
// that is stuck keeps the marker, and a crash or a watchdog kill before the clear is exactly what the next launch sees.

#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#ifdef BPGUARD_TEST
// host unit test (tools/bpguard_test.c): dlopen and the main queue are replaced by recorders
extern void *bpg_test_dlopen(const char *path);
extern const char *bpg_test_dlerror(void);
extern void bpg_test_arm_clear(void);
#define BPG_DLOPEN(p) bpg_test_dlopen(p)
#define BPG_DLERROR() bpg_test_dlerror()
#define BPG_STATIC
#else
#include <dispatch/dispatch.h>
#include <dlfcn.h>
#define BPG_DLOPEN(p) dlopen((p), RTLD_LAZY)
#define BPG_DLERROR() dlerror()
#define BPG_STATIC static
#endif

#define BPG_CLEAR_AFTER_SECONDS 45
#define BPG_CORE_REL "/usr/lib/Backport162/Backport162Core.dylib"

enum {
    BPG_LOADED = 0,            // marker created, clear scheduled, core loaded
    BPG_TRIPPED = 1,           // previous launch never finished booting: core NOT loaded
    BPG_OFF_ALL = 2,           // Backport162.off.all: core NOT loaded
    BPG_LOADED_NOGUARD = 3,    // Backport162.noguard: core loaded, guard off
    BPG_LOADED_NO_SB = 4,      // not SpringBoard: core loaded, no marker
    BPG_LOADED_UNGUARDED = 5,  // marker could not be created (tmp missing / not writable): core loaded without protection
};

static char gTmp[600], gMarker[640], gTripped[640], gLog[640], gDebug[640], gNoGuard[640], gOffAll[640], gCore[640];

static int bpg_exists(const char *p) { struct stat st; return p[0] && stat(p, &st) == 0; }

// "2026-11-01T12:34:56Z": pure arithmetic (gmtime_r reads no timezone file), safe this early in the process
static void bpg_stamp(char *out, size_t n) {
    time_t t = time(NULL);
    struct tm tm;
    if (gmtime_r(&t, &tm) == NULL) { snprintf(out, n, "time?"); return; }
    snprintf(out, n, "%04d-%02d-%02dT%02d:%02d:%02dZ", tm.tm_year + 1900, tm.tm_mon + 1, tm.tm_mday, tm.tm_hour, tm.tm_min, tm.tm_sec);
}

// one write(2) per line, O_APPEND (the core's log and other processes append to the same file), never throws
static void bpg_log(const char *fmt, ...) {
    if (!gLog[0]) return;
    char msg[900], line[1000], ts[40];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(msg, sizeof msg, fmt, ap);
    va_end(ap);
    for (char *c = msg; *c; c++) if (*c == '\n' || *c == '\r') *c = ' ';
    bpg_stamp(ts, sizeof ts);
    int n = snprintf(line, sizeof line, "%s Backport162 loader: %s\n", ts, msg);
    if (n <= 0) return;
    if ((size_t)n >= sizeof line) { n = (int)sizeof line - 1; line[n - 1] = '\n'; }
    int fd = open(gLog, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0644);
    if (fd < 0) return;
    (void)!write(fd, line, (size_t)n);
    close(fd);
}
#define BPG_DEBUG(...) do { if (bpg_exists(gDebug)) bpg_log(__VA_ARGS__); } while (0)

// first bytes of the marker (pid and time of the launch that created it), newlines flattened
static void bpg_read_marker(char *out, size_t n) {
    out[0] = 0;
    int fd = open(gMarker, O_RDONLY | O_CLOEXEC);
    if (fd < 0) return;
    ssize_t r = read(fd, out, n - 1);
    close(fd);
    if (r < 0) r = 0;
    out[r] = 0;
    for (char *c = out; *c; c++) if (*c == '\n' || *c == '\r') *c = ' ';
}

static int bpg_create_marker(void) {
    int fd = open(gMarker, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
    if (fd < 0) return -1;
    char b[96];
    int n = snprintf(b, sizeof b, "pid=%d t=%lld\n", (int)getpid(), (long long)time(NULL));
    if (n > 0) (void)!write(fd, b, (size_t)n);
    close(fd);
    return 0;
}

// the "SpringBoard has finished booting" action: remove the marker (a crash after this point must not trip the next launch)
BPG_STATIC void bpg_clear_marker(void) {
    if (unlink(gMarker) == 0) BPG_DEBUG("boot finished (main queue turning for %d s), marker removed", BPG_CLEAR_AFTER_SECONDS);
    else if (errno != ENOENT) bpg_log("cannot remove %s: %s (the next launch will skip the tweak once)", gMarker, strerror(errno));
}

#ifndef BPGUARD_TEST
static void bpg_clear_cb(void *ctx) { (void)ctx; bpg_clear_marker(); }
// runs on the main queue the first time the main queue is serviced = the main run loop is up; the 45 s are counted from here, on the main queue again,
// so a stuck main thread delays the clear instead of letting a global queue clear it.
static void bpg_armed_cb(void *ctx) {
    dispatch_after_f(dispatch_time(DISPATCH_TIME_NOW, (int64_t)BPG_CLEAR_AFTER_SECONDS * (int64_t)NSEC_PER_SEC), dispatch_get_main_queue(), ctx, bpg_clear_cb);
}
static void bpg_arm_clear(void) { dispatch_async_f(dispatch_get_main_queue(), NULL, bpg_armed_cb); }
#else
static void bpg_arm_clear(void) { bpg_test_arm_clear(); }
#endif

static void bpg_load_core(void) {
    if (access(gCore, F_OK) != 0) { bpg_log("core not loaded: %s is missing (%s)", gCore, strerror(errno)); return; }
    void *h = BPG_DLOPEN(gCore);
    if (!h) {
        const char *e = BPG_DLERROR();
        bpg_log("core not loaded: dlopen(%s) failed: %s", gCore, e ? e : "(no dlerror)");   // always written: the tweak is silently absent otherwise
        return;
    }
    BPG_DEBUG("core loaded: %s", gCore);
}

// jbroot the way Tweak.x gets it (ROOT_PATH_NS: the Theos install prefix, /var/jb for rootless), then the absolute /var/jb; the first one that has a tmp directory
static void bpg_set_paths(const char *root) {
    snprintf(gTmp, sizeof gTmp, "%s/tmp", root);
    snprintf(gMarker, sizeof gMarker, "%s/Backport162.booting", gTmp);
    snprintf(gTripped, sizeof gTripped, "%s/Backport162.tripped", gTmp);
    snprintf(gLog, sizeof gLog, "%s/Backport162.log", gTmp);
    snprintf(gDebug, sizeof gDebug, "%s/Backport162.debug", gTmp);
    snprintf(gNoGuard, sizeof gNoGuard, "%s/Backport162.noguard", gTmp);
    snprintf(gOffAll, sizeof gOffAll, "%s/Backport162.off.all", gTmp);
    snprintf(gCore, sizeof gCore, "%s" BPG_CORE_REL, root);
}

BPG_STATIC int bpg_launch(const char *root, int isSpringBoard) {
    bpg_set_paths(root);

    if (bpg_exists(gOffAll)) {
        if (isSpringBoard) unlink(gMarker);
        BPG_DEBUG("Backport162.off.all exists: core not loaded");
        return BPG_OFF_ALL;
    }
    if (!isSpringBoard) {
        BPG_DEBUG("not SpringBoard: core loaded without the guard");
        bpg_load_core();
        return BPG_LOADED_NO_SB;
    }
    if (bpg_exists(gNoGuard)) {
        unlink(gMarker);
        BPG_DEBUG("Backport162.noguard exists: guard off, core loaded");
        bpg_load_core();
        return BPG_LOADED_NOGUARD;
    }
    if (bpg_exists(gMarker)) {
        char was[96], ts[40];
        bpg_read_marker(was, sizeof was);
        int rm = unlink(gMarker);
        int rmErr = errno;
        bpg_stamp(ts, sizeof ts);
        int fd = open(gTripped, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
        if (fd >= 0) {
            char b[300];
            int n = snprintf(b, sizeof b, "%s tripped (this launch pid=%d did not load the tweak; the previous launch's marker said: %s)\n", ts, (int)getpid(), was[0] ? was : "(empty)");
            if (n > 0) (void)!write(fd, b, (size_t)n < sizeof b ? (size_t)n : sizeof b - 1);
            close(fd);
        }
        bpg_log("BOOT GUARD TRIPPED: the previous SpringBoard launch (%s) loaded the tweak and never finished booting, so the tweak is NOT loaded in this launch "
                "(SpringBoard boots stock); the next launch loads it again. %s. Keep it off with %s/Backport162.off.all, turn the guard off with %s/Backport162.noguard.",
                was[0] ? was : "marker empty", rm == 0 ? "Marker removed" : "Marker could NOT be removed (every launch will skip the tweak until it is deleted by hand)", gTmp, gTmp);
        if (rm != 0) bpg_log("unlink(%s): %s", gMarker, strerror(rmErr));
        return BPG_TRIPPED;
    }
    if (bpg_create_marker() != 0) {
        BPG_DEBUG("cannot create %s (%s): core loaded WITHOUT the guard", gMarker, strerror(errno));
        bpg_load_core();
        return BPG_LOADED_UNGUARDED;
    }
    bpg_arm_clear();
    bpg_load_core();
    return BPG_LOADED;
}

#ifndef BPGUARD_TEST
__attribute__((constructor)) static void bpg_ctor(void) {
    const char *pn = getprogname();
    int sb = pn && strcmp(pn, "SpringBoard") == 0;
    static const char *const kRoots[] = {
#ifdef THEOS_PACKAGE_INSTALL_PREFIX
        THEOS_PACKAGE_INSTALL_PREFIX,
#endif
        "/var/jb",
    };
    const char *root = kRoots[0];
    for (size_t i = 0; i < sizeof kRoots / sizeof kRoots[0]; i++) {
        char t[640];
        struct stat st;
        snprintf(t, sizeof t, "%s/tmp", kRoots[i]);
        if (stat(t, &st) == 0 && S_ISDIR(st.st_mode)) { root = kRoots[i]; break; }
    }
    bpg_launch(root, sb);
}
#endif
