// AudioRouteProbe 0.3.0
//
// Diagnostics for the audio daemon (audiomxd / mediaserverd) on iPadOS 16.0, build 20A8372, plus ONE opt-in
// experiment. Every hook calls the original first and forwards all argument registers unchanged. Without the
// opt-in file the probe changes no behaviour.
//
// Question it answers: when a wired output (USB-C monitor, wired AirPods Max) is connected, why is the
// built-in iPad speaker missing from Control Centre's audio picker? Findings so far (0.2.2 logs): the daemon's
// connected-port list (conn) still contains the speaker port, but cmsmCopyPickableRoutesForRouteConfiguration
// builds its list from Bluetooth ports + AirPlay endpoints + ONE slot for the active non-wireless route, so
// the wired route displaces the speaker.
//
//   conn   _vaemCopyConnectedPortsListForRouteConfiguration  (VAD property 'cprc')  -> port IDs + types
//   incl   _vaemShouldIncludePortTypeForRouteConfiguration   (VAD property 'prsp')  -> include? yes/no
//   pick   _cmsmCopyPickableRoutesForRouteConfiguration                              -> route descriptions
//   rchg   _vaemVADRouteChangeListener                                               -> property change events
//   tap    _FigRoutingManagerPickRouteDescriptorForContext                           -> a route was chosen (logged only)
//
// EXPERIMENT (off by default): if the file /var/tmp/AudioRouteProbe.append exists, the pick hook appends the
// built-in Speaker route to the list for category "Audio/Video" or "MediaPlayback", mode "Default", when it is
// missing. The route description is made by the daemon's own cmsmCreateRouteDescriptionFromPortIDOrRouteConfiguration
// for the speaker port, exactly as the daemon builds Bluetooth entries. The daemon's cached list is never touched
// (a copy is returned). Whether choosing that row actually moves audio is decided by the audio device and is
// exactly what the experiment is meant to find out. Delete the file to switch it off immediately (no reboot).
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
#include <notify.h>
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

#define MAX_LOG_BYTES    (2 * 1024 * 1024)
#define PROBE_VERSION "0.3.0"
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
static const Target T_MKDESC = { "cmsmCreateRouteDescriptionFromPortIDOrRouteConfiguration", 0x196401b78, { 0xd503237f, 0xd10183ff, 0xa9025ff8 } };
static const Target T_VADPK  = { "cmsmCopyVADPickedRouteDescriptionForRouteConfiguration",     0x196403bcc, { 0xd503237f, 0xd10243ff, 0xa9036ffc } };
static const Target T_SPKID  = { "vaemGetCachedSpeakerPortID",                     0x19646bae0, { 0xb02215c8, 0xb947dd00, 0xd65f03c0 } };
static const Target T_TAP    = { "FigRoutingManagerPickRouteDescriptorForContext", 0x1964b2b54, { 0xd503237f, 0xa9ba6ffc, 0xa90167fa } };
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
        if (gFds[i] < 0) continue;
        struct stat st;
        if (fstat(gFds[i], &st) == 0 && st.st_size > MAX_LOG_BYTES) {
            // Rotate, never truncate: 0.2.1 truncated at the cap and threw away the plug-in events.
            const char *p = log_path_for(gFdPath[i]);
            char old[600];
            snprintf(old, sizeof old, "%s.1", p);
            close(gFds[i]);
            (void)rename(p, old);
            gFds[i] = open(p, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0644);
            if (gFds[i] < 0) continue;
        }
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

// ------------------------------------------------------------------ beacons

// The daemon may be unable to write any file, so progress is also reported with Darwin notifications, which
// the SpringBoard side of this tweak (SpringBoardProbe.m) logs. Each beacon is a name plus a 64-bit state:
//   loaded   state = pid                      the probe's constructor ran inside this daemon
//   info     state = 1 ok, 2 kill switch, 3 wrong OS build, 4 crash guard tripped
//   hooks    state = bitmask of installed hooks (bit0 conn, bit1 incl, bit2 pick, bit3 rchg, bit4 tap)
//   ev.*     state = number of times that hook has fired
enum { B_LOADED, B_INFO, B_HOOKS, B_EV_CONN, B_EV_INCL, B_EV_PICK, B_EV_RCHG, B_COUNT };
static const char *const kBeaconNames[B_COUNT] = {
    "com.infernowolf19.audiorouteprobe.loaded", "com.infernowolf19.audiorouteprobe.info",
    "com.infernowolf19.audiorouteprobe.hooks",  "com.infernowolf19.audiorouteprobe.ev.conn",
    "com.infernowolf19.audiorouteprobe.ev.incl", "com.infernowolf19.audiorouteprobe.ev.pick",
    "com.infernowolf19.audiorouteprobe.ev.rchg",
};
static pthread_mutex_t gBeaconMu = PTHREAD_MUTEX_INITIALIZER;
static int      gBeaconTok[B_COUNT];
static bool     gBeaconReady[B_COUNT];
static uint64_t gEventCount[B_COUNT];

static void beacon(int idx, uint64_t state) {
    pthread_mutex_lock(&gBeaconMu);
    if (!gBeaconReady[idx]) {
        gBeaconReady[idx] = true;
        if (notify_register_check(kBeaconNames[idx], &gBeaconTok[idx]) != NOTIFY_STATUS_OK) gBeaconTok[idx] = -1;
    }
    if (gBeaconTok[idx] != -1) notify_set_state(gBeaconTok[idx], state);   // token stays registered so the state persists
    pthread_mutex_unlock(&gBeaconMu);
    notify_post(kBeaconNames[idx]);
}

static void event_beacon(int idx) {
    pthread_mutex_lock(&gBeaconMu);
    uint64_t n = ++gEventCount[idx];
    pthread_mutex_unlock(&gBeaconMu);
    beacon(idx, n);
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
static CFTypeRef (*fn_mkDesc)(uint32_t portID, uintptr_t, uintptr_t, uintptr_t, uintptr_t);   // +1 dictionary
static void (*fn_vadPicked)(CFTypeRef cat, CFTypeRef mode, CFTypeRef a2, CFTypeRef a3, CFTypeRef *out);   // *out +1
static uint32_t (*fn_cachedSpeaker)(void);
static volatile uint32_t gSpeakerId;                 // last port ID seen with type 'pspk' in a connected-port list

// ------------------------------------------------------------------ change detection

// The daemon asks the same questions hundreds of times per second (AirPlay discovery alone filled 4 MB in 80 s), so
// each distinct question is logged only when its answer differs from the previous one.
#define NSEEN 128
static struct { uint64_t key, hash; bool used; } gSeen[NSEEN];
static pthread_mutex_t gSeenMu = PTHREAD_MUTEX_INITIALIZER;

static uint64_t fnv(uint64_t h, const char *s) {
    for (; *s; s++) { h ^= (uint8_t)*s; h *= 1099511628211ull; }
    return h;
}

static bool answer_changed(uint64_t key, uint64_t hash) {
    bool changed = true;
    pthread_mutex_lock(&gSeenMu);
    int slot = -1;
    for (int i = 0; i < NSEEN; i++) {
        if (gSeen[i].used && gSeen[i].key == key) { slot = i; break; }
        if (!gSeen[i].used && slot < 0) slot = i;
    }
    if (slot >= 0) {
        if (gSeen[slot].used && gSeen[slot].hash == hash) changed = false;
        gSeen[slot].used = true; gSeen[slot].key = key; gSeen[slot].hash = hash;
    }
    pthread_mutex_unlock(&gSeenMu);
    return changed;
}

// CFString -> UTF-8 without the pointer that CFCopyDescription prints (it differs on every call).
static void cfstr_c(CFTypeRef t, char *buf, size_t n) {
    buf[0] = 0;
    if (t && plausible_obj(t) && CFGetTypeID(t) == CFStringGetTypeID() && CFStringGetCString((CFStringRef)t, buf, (CFIndex)n, kCFStringEncodingUTF8)) return;
    cfdesc(t, buf, n);
}

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

// All four hooks forward x0..x7 untouched. The first version declared the hooked functions with the argument
// lists I guessed; vaemVADRouteChangeListener actually takes five (x4 is read), so the hook clobbered x4 and the
// real function crashed mediaserverd in CFEqual. Forwarding every argument register makes the hooks transparent
// whatever the true arity (up to 8 register arguments), and nothing here dereferences an argument unless it is
// verified (plausible_obj / CF type checks).
typedef uintptr_t (*Fn8)(uintptr_t, uintptr_t, uintptr_t, uintptr_t, uintptr_t, uintptr_t, uintptr_t, uintptr_t);
#define ARGS8 uintptr_t a0, uintptr_t a1, uintptr_t a2, uintptr_t a3, uintptr_t a4, uintptr_t a5, uintptr_t a6, uintptr_t a7
#define PASS8 a0, a1, a2, a3, a4, a5, a6, a7

// --- conn: connected ports for a route configuration  (uint32 cat, uint32 mode, CFTypeRef arr, int isInput)
static Fn8 orig_conn;
#define FOURCC(a, b, c, d) (((uint32_t)(a) << 24) | ((uint32_t)(b) << 16) | ((uint32_t)(c) << 8) | (uint32_t)(d))

static void note_speaker(CFArrayRef a) {
    if (!fn_portType || !a || !plausible_obj(a) || CFGetTypeID(a) != CFArrayGetTypeID()) return;
    CFIndex cnt = CFArrayGetCount(a);
    for (CFIndex i = 0; i < cnt && i < 32; i++) {
        CFTypeRef e = CFArrayGetValueAtIndex(a, i);
        int32_t id = 0;
        if (e && CFGetTypeID(e) == CFNumberGetTypeID() && CFNumberGetValue((CFNumberRef)e, kCFNumberSInt32Type, &id) &&
            fn_portType((uint32_t)id) == FOURCC('p', 's', 'p', 'k'))
            gSpeakerId = (uint32_t)id;
    }
}

static uintptr_t hook_conn(ARGS8) {
    uintptr_t rv = orig_conn(PASS8);
    note_speaker((CFArrayRef)rv);
    uint32_t cat = (uint32_t)a0, mode = (uint32_t)a1;
    int isInput = (int)a3;
    char desc[400], ports[1400];
    cfdesc((CFTypeRef)a2, desc, sizeof desc);
    format_ports((CFArrayRef)rv, ports, sizeof ports);
    uint64_t h = fnv(fnv(1469598103934665603ull, desc), ports);
    if (answer_changed(((uint64_t)cat << 32) ^ ((uint64_t)mode << 8) ^ (uint64_t)(isInput ? 1 : 2) ^ 0xC0DE000000000000ull, h))
        plog("conn  cat=%u mode=%u in=%d arg=%s -> %s", cat, mode, isInput, desc, ports);
    event_beacon(B_EV_CONN);
    return rv;
}

// --- incl: does this route configuration include a port type?  (uint32 cat, uint32 mode, CFTypeRef arr, uint32 portType)
static Fn8 orig_incl;
static uintptr_t hook_incl(ARGS8) {
    uintptr_t rv = orig_incl(PASS8);
    char tc[8], desc[300];
    cfdesc((CFTypeRef)a2, desc, sizeof desc);
    int r = (int)(rv & 0xff);
    uint64_t h = fnv(1469598103934665603ull, desc) ^ (uint64_t)(r + 1);
    if (answer_changed(((uint64_t)(uint32_t)a0 << 32) ^ ((uint64_t)(uint32_t)a1 << 8) ^ (uint64_t)(uint32_t)a3 * 31u ^ 0x1AC1000000000000ull, h))
        plog("incl  cat=%u mode=%u type=%s arg=%s -> %d", (uint32_t)a0, (uint32_t)a1, fourcc((uint32_t)a3, tc), desc, r);
    event_beacon(B_EV_INCL);
    return rv;
}

// --- experiment: append the built-in Speaker route (see header). Never returns a shorter or different list unless
// every precondition holds; any doubt returns the daemon's own array untouched.
#define APPEND_FLAG "/var/tmp/AudioRouteProbe.append"

static bool cf_is(CFTypeRef t, CFTypeID id) { return t && plausible_obj(t) && CFGetTypeID(t) == id; }

static bool dict_port_is(CFTypeRef d, uint32_t port) {
    if (!cf_is(d, CFDictionaryGetTypeID())) return false;
    CFTypeRef n = CFDictionaryGetValue((CFDictionaryRef)d, CFSTR("PortNumber"));
    int32_t v = 0;
    return cf_is(n, CFNumberGetTypeID()) && CFNumberGetValue((CFNumberRef)n, kCFNumberSInt32Type, &v) && (uint32_t)v == port;
}

// Returns a new +1 array (the caller then releases `r`), or NULL meaning "leave r alone". `why` explains a refusal.
static CFArrayRef speaker_appended(CFTypeRef a0, CFTypeRef a1, uintptr_t a2, uintptr_t a3, CFArrayRef r, const char *cat, const char *mode, const char **why) {
    *why = "";
    if (access(APPEND_FLAG, F_OK) != 0) return NULL;             // opt-in
    if (strcmp(mode, "Default") != 0 || (strcmp(cat, "Audio/Video") != 0 && strcmp(cat, "MediaPlayback") != 0)) return NULL;
    if (a2 != 0) { *why = "a2 set"; return NULL; }
    if (a3 != 0) {
        if (!cf_is((CFTypeRef)a3, CFArrayGetTypeID()) || CFArrayGetCount((CFArrayRef)a3) != 0) { *why = "a3 not an empty array"; return NULL; }
    }
    if (!fn_mkDesc) { *why = "no description builder"; return NULL; }
    if (!cf_is(r, CFArrayGetTypeID())) { *why = "result not an array"; return NULL; }
    CFIndex cnt = CFArrayGetCount(r);
    if (cnt < 1) { *why = "empty list"; return NULL; }
    uint32_t spk = gSpeakerId;
    if (!spk && fn_cachedSpeaker) spk = fn_cachedSpeaker();
    if (!spk) { *why = "speaker port id unknown"; return NULL; }
    for (CFIndex i = 0; i < cnt; i++)
        if (dict_port_is(CFArrayGetValueAtIndex(r, i), spk)) return NULL;     // already listed, nothing to do

    CFTypeRef d = fn_mkDesc(spk, 0, 0, 0, 0);                    // same call form the daemon uses for port IDs
    if (!d) { *why = "builder returned NULL"; return NULL; }
    CFArrayRef out = NULL;
    if (!dict_port_is(d, spk)) { *why = "built description is not the speaker's"; CFRelease(d); return NULL; }

    CFMutableDictionaryRef md = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, (CFDictionaryRef)d);
    CFMutableArrayRef m = CFArrayCreateMutableCopy(kCFAllocatorDefault, 0, r);
    if (md && m) {
        CFTypeRef picked = NULL;                                  // is the speaker the route the audio device is actually using?
        if (fn_vadPicked) fn_vadPicked(a0, a1, NULL, NULL, &picked);
        if (dict_port_is(picked, spk)) CFDictionarySetValue(md, CFSTR("RouteCurrentlyPicked"), kCFBooleanTrue);
        if (picked) CFRelease(picked);
        CFArrayAppendValue(m, md);
        out = m;
        m = NULL;
    } else {
        *why = "allocation failed";
    }
    if (m) CFRelease(m);
    if (md) CFRelease(md);
    CFRelease(d);
    return out;
}

// --- pick: the pickable route descriptions the picker will show  (CFString cat, CFString mode, a2, a3)
static Fn8 orig_pick;
static uintptr_t hook_pick(ARGS8) {
    uintptr_t rv = orig_pick(PASS8);
    char c[120], m[120], x2[300], x3[300];
    cfstr_c((CFTypeRef)a0, c, sizeof c);
    cfstr_c((CFTypeRef)a1, m, sizeof m);
    {
        const char *why = "";
        CFArrayRef added = speaker_appended((CFTypeRef)a0, (CFTypeRef)a1, a2, a3, (CFArrayRef)rv, c, m, &why);
        if (added) {
            CFIndex before = CFArrayGetCount((CFArrayRef)rv);
            CFRelease((CFTypeRef)rv);                            // the daemon's cached array keeps its own reference
            rv = (uintptr_t)added;
            if (answer_changed(fnv(fnv(0xADD5ull, c), m), (uint64_t)before + 1000))
                plog("append: added the built-in Speaker to %s/%s (%ld -> %ld routes)", c, m, (long)before, (long)CFArrayGetCount(added));
        } else if (why[0]) {
            if (answer_changed(fnv(fnv(0xADD6ull, c), m), fnv(1469598103934665603ull, why)))
                plog("append: skipped for %s/%s: %s", c, m, why);
        }
    }
    CFTypeRef r = (CFTypeRef)rv;
    cfdesc((CFTypeRef)a2, x2, sizeof x2);
    cfdesc((CFTypeRef)a3, x3, sizeof x3);
    bool isArray = r && plausible_obj(r) && CFGetTypeID(r) == CFArrayGetTypeID();
    CFIndex cnt = isArray ? CFArrayGetCount((CFArrayRef)r) : 0;
    char d[1100];
    uint64_t h = fnv(fnv(1469598103934665603ull, x2), x3);
    h ^= (uint64_t)cnt + (isArray ? 7 : (r ? 13 : 0));
    for (CFIndex i = 0; i < cnt && i < 24; i++) {
        cfdesc(CFArrayGetValueAtIndex((CFArrayRef)r, i), d, sizeof d);
        h = fnv(h, d);
    }
    if (answer_changed(fnv(fnv(0x91C4ull, c), m), h)) {
        if (isArray) {
            plog("pick  cat=%s mode=%s a2=%s a3=%s -> %ld route(s)", c, m, x2, x3, (long)cnt);
            for (CFIndex i = 0; i < cnt && i < 24; i++) {
                cfdesc(CFArrayGetValueAtIndex((CFArrayRef)r, i), d, sizeof d);
                plog("pick    #%ld %s", (long)i, d);
            }
        } else {
            plog("pick  cat=%s mode=%s a2=%s a3=%s -> %s", c, m, x2, x3, r ? "<not an array>" : "NULL");
        }
    }
    event_beacon(B_EV_PICK);
    return rv;
}

// --- rchg: vaemVADRouteChangeListener. Five register arguments; none is dereferenced here, only logged as numbers.
static Fn8 orig_rchg;
static uintptr_t hook_rchg(ARGS8) {
    plog("rchg  a0=0x%lx a1=0x%lx a2=0x%lx a3=0x%lx a4=0x%lx", (unsigned long)a0, (unsigned long)a1, (unsigned long)a2, (unsigned long)a3, (unsigned long)a4);
    event_beacon(B_EV_RCHG);
    return orig_rchg(PASS8);
}

// --- tap: FigRoutingManagerPickRouteDescriptorForContext(a0, a1 = the route descriptor dictionary, a2, a3). Four
// register arguments and no stack arguments (checked in the disassembly). a1 is only read if it passes the same
// CF-object checks the other hooks use, and only after the callee has been given every register unchanged.
static Fn8 orig_tap;
static uintptr_t hook_tap(ARGS8) {
    char d[900];
    d[0] = 0;
    if (cf_is((CFTypeRef)a1, CFDictionaryGetTypeID())) cfdesc((CFTypeRef)a1, d, sizeof d);
    plog("tap   pick-route-descriptor a0=0x%lx a2=0x%lx a3=0x%lx descriptor=%s", (unsigned long)a0, (unsigned long)a2, (unsigned long)a3, d[0] ? d : "<not a dictionary>");
    uintptr_t rv = orig_tap(PASS8);
    plog("tap   pick-route-descriptor -> %d", (int)(int32_t)rv);
    return rv;
}

// ------------------------------------------------------------------ install

static bool probe_disabled(void) {
    for (int i = 0; i < NLOCATIONS; i++) if (kOffPaths[i][0] && access(kOffPaths[i], F_OK) == 0) return true;
    return access("/var/tmp/AudioRouteProbe.off", F_OK) == 0;   // the only place the sandboxed daemon can see
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
    if (verify(&T_MKDESC)) fn_mkDesc       = (CFTypeRef (*)(uint32_t, uintptr_t, uintptr_t, uintptr_t, uintptr_t))sign_fn(T_MKDESC.addr + (uintptr_t)slide);
    if (verify(&T_VADPK))  fn_vadPicked    = (void (*)(CFTypeRef, CFTypeRef, CFTypeRef, CFTypeRef, CFTypeRef *))sign_fn(T_VADPK.addr + (uintptr_t)slide);
    if (verify(&T_SPKID))  fn_cachedSpeaker = (uint32_t (*)(void))sign_fn(T_SPKID.addr + (uintptr_t)slide);

    hook_one(&T_CONN, (void *)hook_conn, (void **)&orig_conn);
    hook_one(&T_INCL, (void *)hook_incl, (void **)&orig_incl);
    hook_one(&T_PICK, (void *)hook_pick, (void **)&orig_pick);
    hook_one(&T_RCHG, (void *)hook_rchg, (void **)&orig_rchg);
    hook_one(&T_TAP,  (void *)hook_tap,  (void **)&orig_tap);
    uint64_t mask = (orig_conn ? 1u : 0u) | (orig_incl ? 2u : 0u) | (orig_pick ? 4u : 0u) | (orig_rchg ? 8u : 0u) | (orig_tap ? 16u : 0u);
    beacon(B_HOOKS, mask);
    plog("probe active (hook mask 0x%llx): open the audio picker, plug/unplug outputs, then read this log", (unsigned long long)mask);
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
    snprintf(path, sizeof path, "%s." PROBE_VERSION ".boot", log_path_for(idx));   // per-version: a new build re-arms itself
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
    beacon(B_LOADED, (uint64_t)getpid());            // visible in the SpringBoard log even if no file can be written here
    resolve_paths();                                 // jbroot-prefixed log / kill-switch locations
    if (probe_disabled()) { beacon(B_INFO, 2); plog("kill switch present; probe inactive"); return; }
    plog("---- AudioRouteProbe " PROBE_VERSION " loaded");
    pthread_mutex_lock(&gMu);
    if (gNFds < 0) plog_open_locked();
    int nopen = gNFds;
    pthread_mutex_unlock(&gMu);
    if (nopen == 0) os_log(OS_LOG_DEFAULT, "[AudioRouteProbe] no log file could be opened anywhere (sandbox?)");
    for (int i = 0; i < nopen; i++) plog("log file: %s", log_path_for(gFdPath[i]));
    if (!os_build_ok()) { beacon(B_INFO, 3); return; }
    bool tripped;
    boot_guard(&tripped);
    if (tripped) { beacon(B_INFO, 4); return; }
    beacon(B_INFO, 1);
    _dyld_register_func_for_add_image(image_added);   // also fires for images that are already mapped
}
