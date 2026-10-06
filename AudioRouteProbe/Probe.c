// AudioRouteProbe
//
// PASSIVE diagnostics for the audio daemon (audiomxd / mediaserverd) on iPadOS 16.0, build 20A8372.
// It changes no behaviour: every hook calls the original first and only then logs.
//
// Question it answers: when a wired output (USB-C monitor, wired AirPods Max) is connected, why is the
// built-in iPad speaker missing from Control Centre's audio picker? The picker list is built in
// MediaExperience.framework (hosted by audiomxd) from the VirtualAudio HAL plug-in's "connected ports"
// for the current route configuration. We log, around that pipeline:
//
//   conn   _vaemCopyConnectedPortsListForRouteConfiguration  (VAD property 'cprc')  -> port IDs + types
//   incl   _vaemShouldIncludePortTypeForRouteConfiguration   (VAD property 'prsp')  -> include? yes/no
//   pick   _cmsmCopyPickableRoutesForRouteConfiguration                              -> route descriptions
//   rchg   _vaemVADRouteChangeListener                                               -> property change events
//
// The target functions are private symbols, so they are located by their address in the 20A8372 shared
// cache plus the cache slide. Before hooking anything the probe verifies, in this order:
//   1. kern.osversion == 20A8372
//   2. MediaExperience is mapped in this process
//   3. the first three instructions of each target match what was disassembled from 20A8372
// Anything that does not match is left alone and the log says so.
//
// Output: every location in kLogRel that opens (all under the jailbreak root, resolved with libroot).
// Kill switch: create any file listed in kOffRel (jbroot-relative) and restart the daemon. Crash guard: 5 consecutive launches that did not stay up 25 s disable the probe.

#include <CoreFoundation/CoreFoundation.h>
#include <mach-o/dyld.h>
#include <sys/sysctl.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <malloc/malloc.h>
#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <pthread.h>
#include <unistd.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <os/log.h>
#include <substrate.h>
#include <limits.h>
#include <errno.h>
#include <rootless.h>        // ROOT_PATH(): jailbreak-root prefix resolved at runtime via libroot
#if __has_feature(ptrauth_calls)
#include <ptrauth.h>
#endif

// ------------------------------------------------------------------ configuration

#define PROBE_OS_BUILD   "20A8372"
#define MEDIAEXP_IMAGE   "/System/Library/PrivateFrameworks/MediaExperience.framework/MediaExperience"

// Rootless convention: every file this tweak creates lives under the jailbreak root, never at a rootful
// path. The prefix is resolved at runtime by libroot (ROOT_PATH), so relocated jbroots keep working, and
// nothing is left behind on the rootful filesystem. The paths below are *jbroot-relative*.
// The daemon may be sandboxed and runs as a different user than mobile, so several locations are tried
// and every one that opens gets the log:
//   /tmp                          world-writable, physically inside the jbroot
//   /var/mobile/Library/Logs      mobile-owned (jbroot's var/mobile)
//   /var/log                      root-owned, physically inside the jbroot
#define NLOCATIONS 3
static const char *const kLogRel[NLOCATIONS] = {
    "/tmp/AudioRouteProbe.log",
    "/var/mobile/Library/Logs/AudioRouteProbe.log",
    "/var/log/AudioRouteProbe.log",
};
static const char *const kOffRel[NLOCATIONS] = {
    "/tmp/AudioRouteProbe.off",
    "/var/mobile/Library/Preferences/AudioRouteProbe.off",
    "/var/log/AudioRouteProbe.off",
};
// Resolved (absolute) paths, filled in once by resolve_paths() before anything else runs.
static char kLogPaths[NLOCATIONS][PATH_MAX];
static char kOffPaths[NLOCATIONS][PATH_MAX];

// Fallback, used ONLY if none of the jbroot locations above can be opened (e.g. the daemon's sandbox blocks
// writes under the jbroot): the daemon's own per-process temp and cache directories. Every sandbox profile
// allows those, the OS cleans them up, and they are not jailbreak paths. Find them with:
//   sudo find /private/var/folders -name 'AudioRouteProbe.log' 2>/dev/null
#define NFALLBACK 2
static char kFallbackPaths[NFALLBACK][PATH_MAX];

static const char *log_path_for(int idx) {            // idx < NLOCATIONS: jbroot location; else fallback
    return idx < NLOCATIONS ? kLogPaths[idx] : kFallbackPaths[idx - NLOCATIONS];
}

static void resolve_one(char *dst, const char *jbrootRelative) {
    // ROOT_PATH() returns a pointer to a per-call-site static buffer, so copy it out immediately.
    const char *p = ROOT_PATH(jbrootRelative);
    if (p) strlcpy(dst, p, PATH_MAX);
    else dst[0] = 0;
}

static void resolve_paths(void) {
    for (int i = 0; i < NLOCATIONS; i++) {
        resolve_one(kLogPaths[i], kLogRel[i]);
        resolve_one(kOffPaths[i], kOffRel[i]);
    }
    static const int dirs[NFALLBACK] = { _CS_DARWIN_USER_TEMP_DIR, _CS_DARWIN_USER_CACHE_DIR };
    for (int i = 0; i < NFALLBACK; i++) {
        char dir[PATH_MAX];
        size_t n = confstr(dirs[i], dir, sizeof dir);   // ends with '/'
        kFallbackPaths[i][0] = 0;
        if (n > 0 && n <= sizeof dir) snprintf(kFallbackPaths[i], PATH_MAX, "%sAudioRouteProbe.log", dir);
    }
}

#define MAX_LOG_BYTES    (4 * 1024 * 1024)
#define MAX_BOOT_STRIKES 5
#define STABLE_SECONDS   25

// Targets: address in the (unslid) 20A8372 arm64e dyld shared cache + the first three instruction words.
typedef struct {
    const char *name;
    uintptr_t   addr;
    uint32_t    word[3];
} Target;

static const Target T_CONN  = { "vaemCopyConnectedPortsListForRouteConfiguration", 0x1963ff29c, { 0xd503237f, 0xd10143ff, 0xa90257f6 } };
static const Target T_PICK  = { "cmsmCopyPickableRoutesForRouteConfiguration",     0x19641d98c, { 0xd503237f, 0xd10443ff, 0xa90b6ffc } };
static const Target T_INCL  = { "vaemShouldIncludePortTypeForRouteConfiguration",  0x196401f34, { 0xd503237f, 0xd10103ff, 0xa9024ff4 } };
static const Target T_RCHG  = { "vaemVADRouteChangeListener",                      0x19640a224, { 0xd503237f, 0x6db923e9, 0xa9016ffc } };
static const Target T_PTYPE = { "vaeGetPortTypeFromPortID",                        0x19640545c, { 0xd503237f, 0xd100c3ff, 0xa9027bfd } };
static const Target T_ISHP  = { "vaeIsHeadphonesPort",                             0x19641a580, { 0xd503237f, 0xa9bd57f6, 0xa9014ff4 } };

// ------------------------------------------------------------------ logging

static pthread_mutex_t gMu = PTHREAD_MUTEX_INITIALIZER;
static int  gFds[8];
static int  gFdPath[8];                              // index into kLogPaths for each open fd
static int  gNFds = -1;                              // -1: not opened yet

static char gOpenReport[2048];                       // why each location failed; written into the log once

static void plog_try_open_locked(int idx) {
    const char *path = log_path_for(idx);
    if (!path[0]) return;
    int fd = open(path, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0644);
    if (fd >= 0) {
        if (gNFds < 8) { gFds[gNFds] = fd; gFdPath[gNFds] = idx; gNFds++; }
        else close(fd);
    } else {
        size_t used = strlen(gOpenReport);
        snprintf(gOpenReport + used, sizeof gOpenReport - used, "  %s: %s\n", path, strerror(errno));
    }
}

static void plog_open_locked(void) {
    gNFds = 0;
    gOpenReport[0] = 0;
    for (int i = 0; i < NLOCATIONS; i++) plog_try_open_locked(i);
    bool usedFallback = false;
    if (gNFds == 0) {                                // jbroot locations all failed: use the daemon's temp dirs
        usedFallback = true;
        for (int i = 0; i < NFALLBACK; i++) plog_try_open_locked(NLOCATIONS + i);
    }
    if (gNFds > 0) {                                 // make the log explain itself
        char head[2600];
        snprintf(head, sizeof head, "[probe] uid=%d euid=%d pid=%d%s%s%s\n", (int)getuid(), (int)geteuid(), (int)getpid(),
                 usedFallback ? " (jbroot log locations not writable; using the daemon's temp dir)" : "",
                 gOpenReport[0] ? "; failed to open:\n" : "", gOpenReport);
        for (int i = 0; i < gNFds; i++) (void)!write(gFds[i], head, strlen(head));
    }
    if (gOpenReport[0]) os_log(OS_LOG_DEFAULT, "[AudioRouteProbe] log open failures:\n%{public}s", gOpenReport);
}

static void plog_locked(const char *msg) {
    if (gNFds < 0) plog_open_locked();
    for (int i = 0; i < gNFds; i++) {                // nothing opened: os_log below still has it
        struct stat st;
        if (fstat(gFds[i], &st) == 0 && st.st_size > MAX_LOG_BYTES) (void)ftruncate(gFds[i], 0);
        (void)!write(gFds[i], msg, strlen(msg));
    }
}

static void plog(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
static void plog(const char *fmt, ...) {
    char body[6144];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(body, sizeof body, fmt, ap);
    va_end(ap);

    struct timeval tv; gettimeofday(&tv, NULL);
    struct tm tmv; time_t sec = tv.tv_sec; localtime_r(&sec, &tmv);
    char line[6400];
    snprintf(line, sizeof line, "%02d:%02d:%02d.%03d [%s:%d] %s\n",
             tmv.tm_hour, tmv.tm_min, tmv.tm_sec, (int)(tv.tv_usec / 1000), getprogname(), (int)getpid(), body);

    os_log(OS_LOG_DEFAULT, "[AudioRouteProbe] %{public}s", body);
    pthread_mutex_lock(&gMu);
    plog_locked(line);
    pthread_mutex_unlock(&gMu);
}

// ------------------------------------------------------------------ safe CF description

// A pointer we are willing to hand to CoreFoundation: tagged, or a malloc block, or inside a loaded image.
static bool plausible_obj(const void *p) {
    uintptr_t v = (uintptr_t)p;
    if (!v) return false;
    if (v & 1) return true;                         // tagged pointer, CF knows how to read it
    if (v & 7) return false;
    if (malloc_size(p) > 0) return true;
    Dl_info info;
    return dladdr(p, &info) != 0;
}

static void squash(char *s) {                       // newlines/tabs -> space, collapse runs of spaces
    char *w = s;
    bool lastSpace = false;
    for (char *r = s; *r; r++) {
        char c = (*r == '\n' || *r == '\t' || *r == '\r') ? ' ' : *r;
        if (c == ' ' && lastSpace) continue;
        lastSpace = (c == ' ');
        *w++ = c;
    }
    *w = 0;
}

static void cfdesc(CFTypeRef o, char *buf, size_t n) {
    if (!o) { snprintf(buf, n, "NULL"); return; }
    if (!plausible_obj(o)) { snprintf(buf, n, "<ptr %p>", o); return; }
    CFStringRef d = CFCopyDescription(o);
    if (!d) { snprintf(buf, n, "<no description>"); return; }
    CFIndex len = CFStringGetLength(d);
    CFIndex used = 0;
    CFIndex take = len < (CFIndex)(n - 1) ? len : (CFIndex)(n - 1);
    CFStringGetBytes(d, CFRangeMake(0, take), kCFStringEncodingUTF8, '?', false, (UInt8 *)buf, (CFIndex)(n - 1), &used);
    buf[used] = 0;
    CFRelease(d);
    squash(buf);
}

static const char *fourcc(uint32_t v, char out[8]) {
    char c[4] = { (char)(v >> 24), (char)(v >> 16), (char)(v >> 8), (char)v };
    bool printable = true;
    for (int i = 0; i < 4; i++) if (c[i] < 0x20 || c[i] > 0x7e) printable = false;
    if (printable) { out[0] = c[0]; out[1] = c[1]; out[2] = c[2]; out[3] = c[3]; out[4] = 0; }
    else snprintf(out, 8, "0x%x", v);
    return out;
}

// ------------------------------------------------------------------ function plumbing

static void *sign_fn(uintptr_t a) {
#if __has_feature(ptrauth_calls)
    return ptrauth_sign_unauthenticated((void *)a, ptrauth_key_function_pointer, 0);
#else
    return (void *)a;
#endif
}

static intptr_t gSlide;

static bool verify(const Target *t) {
    const uint32_t *p = (const uint32_t *)(t->addr + (uintptr_t)gSlide);
    for (int i = 0; i < 3; i++) {
        if (p[i] != t->word[i]) {
            plog("target %s: prologue mismatch at word %d (have %08x, want %08x); NOT hooking", t->name, i, p[i], t->word[i]);
            return false;
        }
    }
    return true;
}

static uint32_t (*fn_portType)(uint32_t);
static uint32_t (*fn_isHeadphones)(uint32_t);

// ------------------------------------------------------------------ hooks

static void format_ports(CFArrayRef a, char *buf, size_t n) {
    buf[0] = 0;
    if (!a) { snprintf(buf, n, "NULL"); return; }
    if (!plausible_obj(a) || CFGetTypeID(a) != CFArrayGetTypeID()) { snprintf(buf, n, "<not an array %p>", (const void *)a); return; }
    CFIndex cnt = CFArrayGetCount(a);
    size_t off = (size_t)snprintf(buf, n, "%ld:", (long)cnt);
    for (CFIndex i = 0; i < cnt && off + 48 < n; i++) {
        CFTypeRef e = CFArrayGetValueAtIndex(a, i);
        int32_t id = 0;
        if (e && CFGetTypeID(e) == CFNumberGetTypeID() && CFNumberGetValue((CFNumberRef)e, kCFNumberSInt32Type, &id)) {
            char tc[8] = "?";
            int hp = -1;
            if (fn_portType) fourcc(fn_portType((uint32_t)id), tc);
            if (fn_isHeadphones) hp = fn_isHeadphones((uint32_t)id) ? 1 : 0;
            off += (size_t)snprintf(buf + off, n - off, " [id=%d type=%s hp=%d]", id, tc, hp);
        } else {
            off += (size_t)snprintf(buf + off, n - off, " [non-number]");
        }
    }
}

// --- conn: connected ports for a route configuration
typedef CFArrayRef (*ConnFn)(uint32_t cat, uint32_t mode, CFTypeRef arr, int isInput);
static ConnFn orig_conn;
static CFArrayRef hook_conn(uint32_t cat, uint32_t mode, CFTypeRef arr, int isInput) {
    CFArrayRef r = orig_conn(cat, mode, arr, isInput);
    char a2[400], ports[1400];
    cfdesc(arr, a2, sizeof a2);
    format_ports(r, ports, sizeof ports);
    plog("conn  cat=%u mode=%u in=%d arg=%s -> %s", cat, mode, isInput, a2, ports);
    return r;
}

// --- incl: does this route configuration include a port type?
typedef bool (*InclFn)(uint32_t cat, uint32_t mode, CFTypeRef arr, uint32_t portType);
static InclFn orig_incl;
static bool hook_incl(uint32_t cat, uint32_t mode, CFTypeRef arr, uint32_t portType) {
    bool r = orig_incl(cat, mode, arr, portType);
    char tc[8], a2[300];
    cfdesc(arr, a2, sizeof a2);
    plog("incl  cat=%u mode=%u type=%s arg=%s -> %d", cat, mode, fourcc(portType, tc), a2, (int)r);
    return r;
}

// --- pick: the pickable route descriptions the picker will show
typedef CFArrayRef (*PickFn)(CFTypeRef cat, CFTypeRef mode, CFTypeRef a2, CFTypeRef a3);
static PickFn orig_pick;
static CFArrayRef hook_pick(CFTypeRef cat, CFTypeRef mode, CFTypeRef a2, CFTypeRef a3) {
    CFArrayRef r = orig_pick(cat, mode, a2, a3);
    char c[200], m[200], x2[400], x3[400];
    cfdesc(cat, c, sizeof c);
    cfdesc(mode, m, sizeof m);
    cfdesc(a2, x2, sizeof x2);
    cfdesc(a3, x3, sizeof x3);
    if (r && plausible_obj(r) && CFGetTypeID(r) == CFArrayGetTypeID()) {
        CFIndex cnt = CFArrayGetCount(r);
        plog("pick  cat=%s mode=%s a2=%s a3=%s -> %ld route(s)", c, m, x2, x3, (long)cnt);
        for (CFIndex i = 0; i < cnt && i < 24; i++) {
            char d[1100];
            cfdesc(CFArrayGetValueAtIndex(r, i), d, sizeof d);
            plog("pick    #%ld %s", (long)i, d);
        }
    } else {
        plog("pick  cat=%s mode=%s a2=%s a3=%s -> %s", c, m, x2, x3, r ? "<not an array>" : "NULL");
    }
    return r;
}

// --- rchg: AudioObjectPropertyListenerProc registered on the VAD
typedef struct { uint32_t selector, scope, element; } AOAddr;
typedef int32_t (*RchgFn)(uint32_t objectID, uint32_t n, const AOAddr *addrs, void *client);
static RchgFn orig_rchg;
static int32_t hook_rchg(uint32_t objectID, uint32_t n, const AOAddr *addrs, void *client) {
    if (addrs && n > 0 && n < 64) {
        char line[900];
        size_t off = (size_t)snprintf(line, sizeof line, "rchg  obj=%u n=%u", objectID, n);
        for (uint32_t i = 0; i < n && i < 12 && off + 40 < sizeof line; i++) {
            char s[8], sc[8];
            off += (size_t)snprintf(line + off, sizeof line - off, " {%s/%s/%u}",
                                    fourcc(addrs[i].selector, s), fourcc(addrs[i].scope, sc), addrs[i].element);
        }
        plog("%s", line);
    }
    return orig_rchg(objectID, n, addrs, client);
}

// ------------------------------------------------------------------ install

static bool probe_disabled(void) {
    for (int i = 0; i < NLOCATIONS; i++) if (kOffPaths[i][0] && access(kOffPaths[i], F_OK) == 0) return true;
    return false;
}

static bool os_build_ok(void) {
    char buf[64] = {0};
    size_t len = sizeof buf;
    if (sysctlbyname("kern.osversion", buf, &len, NULL, 0) != 0) return false;
    if (strcmp(buf, PROBE_OS_BUILD) != 0) { plog("kern.osversion=%s (need %s); probe inactive", buf, PROBE_OS_BUILD); return false; }
    return true;
}

static void hook_one(const Target *t, void *replacement, void **orig) {
    if (!verify(t)) return;
    MSHookFunction(sign_fn(t->addr + (uintptr_t)gSlide), replacement, orig);
    plog("hooked %s at %p", t->name, (void *)(t->addr + (uintptr_t)gSlide));
}

static bool gInstalled;

static void install(intptr_t slide) {
    if (gInstalled) return;
    gInstalled = true;
    gSlide = slide;
    plog("MediaExperience mapped, cache slide=0x%lx", (long)slide);

    if (verify(&T_PTYPE)) fn_portType     = (uint32_t (*)(uint32_t))sign_fn(T_PTYPE.addr + (uintptr_t)slide);
    if (verify(&T_ISHP))  fn_isHeadphones = (uint32_t (*)(uint32_t))sign_fn(T_ISHP.addr + (uintptr_t)slide);

    hook_one(&T_CONN, (void *)hook_conn, (void **)&orig_conn);
    hook_one(&T_INCL, (void *)hook_incl, (void **)&orig_incl);
    hook_one(&T_PICK, (void *)hook_pick, (void **)&orig_pick);
    hook_one(&T_RCHG, (void *)hook_rchg, (void **)&orig_rchg);
    plog("probe active: open the audio picker, plug/unplug outputs, then read this log");
}

static void image_added(const struct mach_header *mh, intptr_t slide) {
    Dl_info info;
    if (!dladdr(mh, &info) || !info.dli_fname) return;
    if (strcmp(info.dli_fname, MEDIAEXP_IMAGE) != 0) return;
    install(slide);
}

// Crash-loop guard: a ".boot" counter next to whichever log file opened.
static void boot_guard(bool *tripped) {
    *tripped = false;
    pthread_mutex_lock(&gMu);
    if (gNFds < 0) plog_open_locked();
    int idx = gNFds > 0 ? gFdPath[0] : -1;
    pthread_mutex_unlock(&gMu);
    if (idx < 0) return;                             // no writable location: no guard, rely on safe mode
    char path[512];
    snprintf(path, sizeof path, "%s.boot", log_path_for(idx));
    int strikes = 0;
    FILE *f = fopen(path, "r");
    if (f) { if (fscanf(f, "%d", &strikes) != 1) strikes = 0; fclose(f); }
    if (strikes >= MAX_BOOT_STRIKES) { *tripped = true; plog("crash guard: %d short-lived launches in a row; probe disabled (delete %s to re-arm)", strikes, path); return; }
    f = fopen(path, "w");
    if (f) { fprintf(f, "%d", strikes + 1); fclose(f); }
    static char gBootPath[512];
    snprintf(gBootPath, sizeof gBootPath, "%s", path);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)STABLE_SECONDS * NSEC_PER_SEC),
                   dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ unlink(gBootPath); });
}

__attribute__((constructor))
static void probe_init(void) {
    const char *name = getprogname();
    if (!name || (strcmp(name, "audiomxd") != 0 && strcmp(name, "mediaserverd") != 0)) return;
    resolve_paths();                                 // jbroot-prefixed log / kill-switch locations
    if (probe_disabled()) { plog("kill switch present; probe inactive"); return; }
    plog("---- AudioRouteProbe 0.1.1 loaded");
    pthread_mutex_lock(&gMu);
    if (gNFds < 0) plog_open_locked();
    int nopen = gNFds;
    pthread_mutex_unlock(&gMu);
    if (nopen == 0) os_log(OS_LOG_DEFAULT, "[AudioRouteProbe] no log file could be opened anywhere (sandbox?)");
    for (int i = 0; i < nopen; i++) plog("log file: %s", log_path_for(gFdPath[i]));
    if (!os_build_ok()) return;
    bool tripped;
    boot_guard(&tripped);
    if (tripped) return;
    _dyld_register_func_for_add_image(image_added);   // also fires for images that are already mapped
}
