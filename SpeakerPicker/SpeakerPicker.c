// SpeakerPicker
//
// Keeps the iPad's built-in speaker selectable in the audio picker (Control Centre / Now Playing) while a USB-C
// monitor or wired headphones are connected. iPadOS 16.0, build 20A8372, arm64e, rootless jailbreak.
//
// Why the speaker disappears (established from device logs, see README): the audio daemon's list of pickable routes is
// Bluetooth ports + AirPlay endpoints + ONE slot for the active non-wireless route, so a wired route displaces the
// speaker. Choosing the speaker is then refused by a policy table that marks playback categories "CannotOverride".
//
// What this tweak does, inside mediaserverd / audiomxd only:
//   1. Hooks cmsmCopyPickableRoutesForRouteConfiguration (the single hook). When the caller asks for the plain
//      Audio/Video or MediaPlayback list (any mode: video apps such as Netflix use MoviePlayback), a copy of the result is returned with the route of any
//      connected speaker / display / wired-headphone port that is missing from it appended. The daemon's own cached
//      list is never modified. Route descriptions are built by the daemon's own function, exactly as it builds Bluetooth
//      entries.
//   2. Replaces, once, the daemon's category -> overridability table (a CFDictionary global) by a copy in which every
//      CannotOverride says CanOverride, so the "Speaker" override request that the picker sends is accepted.
//
// Resource use: one hook, no timers, no threads, no polling, no file writes while running. Per call that does not
// concern Audio/Video or MediaPlayback the added cost is two string compares. Logging goes to the unified log (os_log,
// a handful of lines per boot); a rotating file log is written only while /var/tmp/SpeakerPicker.debug exists.
//
// Safety: hooks are installed only if kern.osversion is exactly 20A8372 and the first three instructions of every
// private function used match what was disassembled from that build; the policy table is touched only if it is a
// 35-entry CFDictionary in writable memory. Crash guard: five launches in a row that die within 25 s disable the
// tweak for this version. Kill switch: create /var/tmp/SpeakerPicker.off (takes effect within a second and restores
// the original policy table).
//
// Paths: the audio daemon is sandboxed and cannot see the jailbreak root, so the few files it uses live in the
// system temp directory /var/tmp (which the daemon can read and write), never in a rootful tweak location.

#include <CoreFoundation/CoreFoundation.h>
#include <mach/mach.h>
#include <mach-o/dyld.h>
#include <malloc/malloc.h>
#include <sys/sysctl.h>
#include <sys/stat.h>
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
#if __has_feature(ptrauth_calls)
#include <ptrauth.h>
#endif

#define TWEAK_VERSION     "1.0.1"
#define REQUIRED_OS_BUILD "20A8372"
#define MEDIAEXP_IMAGE    "/System/Library/PrivateFrameworks/MediaExperience.framework/MediaExperience"

#define OFF_FILE          "/var/tmp/SpeakerPicker.off"
#define DEBUG_FILE        "/var/tmp/SpeakerPicker.debug"
#define LOG_FILE          "/var/tmp/SpeakerPicker.log"
#define BOOT_FILE         "/var/tmp/SpeakerPicker." TWEAK_VERSION ".boot"
#define MAX_BOOT_STRIKES  5
#define STABLE_SECONDS    25
#define MAX_LOG_BYTES     (256 * 1024)

// ------------------------------------------------------------------ logging

static os_log_t gLog;

static void info(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
static void info(const char *fmt, ...) {            // unified log; callers keep this to a few lines per boot
    char msg[256];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(msg, sizeof msg, fmt, ap);
    va_end(ap);
    os_log(gLog, "%{public}s", msg);
}

// Opt-in file log: only while DEBUG_FILE exists, only on state changes, capped at MAX_LOG_BYTES (the file is simply
// restarted when it fills up).
static void dlog(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
static void dlog(const char *fmt, ...) {
    if (access(DEBUG_FILE, F_OK) != 0) return;
    char msg[400];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(msg, sizeof msg, fmt, ap);
    va_end(ap);
    struct stat st;
    int flags = O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC;
    if (stat(LOG_FILE, &st) == 0 && st.st_size > MAX_LOG_BYTES) flags |= O_TRUNC;
    int fd = open(LOG_FILE, flags, 0644);
    if (fd < 0) return;
    char line[460];
    time_t now = time(NULL);
    struct tm tmv;
    localtime_r(&now, &tmv);
    int n = snprintf(line, sizeof line, "%02d:%02d:%02d %s\n", tmv.tm_hour, tmv.tm_min, tmv.tm_sec, msg);
    if (n > 0) (void)!write(fd, line, (size_t)n);
    close(fd);
}

// ------------------------------------------------------------------ targets (all in MediaExperience, build 20A8372)

typedef struct {
    const char *name;
    uintptr_t   addr;
    uint32_t    word[3];                            // first three instructions
} Target;

static const Target T_PICK   = { "cmsmCopyPickableRoutesForRouteConfiguration",             0x19641d98c, { 0xd503237f, 0xd10443ff, 0xa90b6ffc } };
static const Target T_CONN   = { "vaemCopyConnectedPortsListForRouteConfiguration",         0x1963ff29c, { 0xd503237f, 0xd10143ff, 0xa90257f6 } };
static const Target T_PTYPE  = { "vaeGetPortTypeFromPortID",                                0x19640545c, { 0xd503237f, 0xd100c3ff, 0xa9027bfd } };
static const Target T_MKDESC = { "cmsmCreateRouteDescriptionFromPortIDOrRouteConfiguration", 0x196401b78, { 0xd503237f, 0xd10183ff, 0xa9025ff8 } };
static const Target T_VADPK  = { "cmsmCopyVADPickedRouteDescriptionForRouteConfiguration",   0x196403bcc, { 0xd503237f, 0xd10243ff, 0xa9036ffc } };

// Data: category -> overridability CFDictionary (35 entries), and the two CFString constants it holds.
#define G_OVRMAP          0x1da725d58ull
#define G_CAN_OVERRIDE    0x1d5e803d8ull           /* kCMSessionOutputOverridability_CanOverride    */
#define G_CANNOT_OVERRIDE 0x1d5e803e0ull           /* kCMSessionOutputOverridability_CannotOverride */

#define VAD_CAT_AV        0x63736176u              /* 'csav' */
#define VAD_MODE_DEFAULT  0x696d6466u              /* 'imdf' */
#define FOURCC(a, b, c, d) (((uint32_t)(a) << 24) | ((uint32_t)(b) << 16) | ((uint32_t)(c) << 8) | (uint32_t)(d))

static intptr_t gSlide;

static void *sign_fn(uintptr_t a) {
#if __has_feature(ptrauth_calls)
    return ptrauth_sign_unauthenticated((void *)a, ptrauth_key_function_pointer, 0);
#else
    return (void *)a;
#endif
}

static bool verify(const Target *t) {
    const uint32_t *p = (const uint32_t *)(t->addr + (uintptr_t)gSlide);
    for (int i = 0; i < 3; i++) {
        if (p[i] != t->word[i]) {
            info("%s: prologue mismatch at word %d (have %08x, want %08x); tweak inactive", t->name, i, p[i], t->word[i]);
            return false;
        }
    }
    return true;
}

// Functions called directly (not hooked). Argument counts were read off the disassembly: none of these reads a
// stack argument.
static uint32_t (*fn_portType)(uint32_t);
static CFArrayRef (*fn_conn)(uint32_t cat, uint32_t mode, CFTypeRef arr, int isInput);
static CFTypeRef (*fn_mkDesc)(uint32_t portID, uintptr_t, uintptr_t, uintptr_t, uintptr_t);                    // +1 dictionary
static void (*fn_vadPicked)(CFTypeRef cat, CFTypeRef mode, CFTypeRef a2, CFTypeRef a3, CFTypeRef *out);          // *out is +1

typedef uintptr_t (*Fn8)(uintptr_t, uintptr_t, uintptr_t, uintptr_t, uintptr_t, uintptr_t, uintptr_t, uintptr_t);
#define ARGS8 uintptr_t a0, uintptr_t a1, uintptr_t a2, uintptr_t a3, uintptr_t a4, uintptr_t a5, uintptr_t a6, uintptr_t a7
#define PASS8 a0, a1, a2, a3, a4, a5, a6, a7
static Fn8 orig_pick;

// ------------------------------------------------------------------ safe CoreFoundation helpers

// arm64 tagged pointers (short strings, small numbers) have the HIGH bit set; ordinary objects are malloc blocks or
// constants inside a loaded image.
static bool maybe_cf(CFTypeRef t) {
    uintptr_t v = (uintptr_t)t;
    if (!v) return false;
    if ((v >> 63) != 0) return true;
    if (v & 7) return false;
    if (malloc_size(t) > 0) return true;
    Dl_info di;
    return dladdr(t, &di) != 0;
}

static bool cf_is(CFTypeRef t, CFTypeID id) { return maybe_cf(t) && CFGetTypeID(t) == id; }

static bool string_is(CFTypeRef t, CFStringRef want) { return cf_is(t, CFStringGetTypeID()) && CFEqual(t, want); }

// Only for values taken out of a CF container (array element / dictionary value): CF objects by construction.
static bool is_cf_number(CFTypeRef t) { return t && maybe_cf(t) && CFGetTypeID(t) == CFNumberGetTypeID(); }

static bool dict_port_is(CFTypeRef d, uint32_t port) {
    if (!cf_is(d, CFDictionaryGetTypeID())) return false;
    CFTypeRef n = CFDictionaryGetValue((CFDictionaryRef)d, CFSTR("PortNumber"));
    int32_t v = 0;
    return is_cf_number(n) && CFNumberGetValue((CFNumberRef)n, kCFNumberSInt32Type, &v) && (uint32_t)v == port;
}

static uint64_t now_ns(void) { return clock_gettime_nsec_np(CLOCK_UPTIME_RAW); }

// ------------------------------------------------------------------ kill switch (checked at most once a second)

static CFDictionaryRef gOvrOrig, gOvrPatched;
static pthread_mutex_t gOvrMu = PTHREAD_MUTEX_INITIALIZER;
static int gPolicyFailures;

static bool killed(void) {
    static uint64_t next;
    static bool last;
    uint64_t t = now_ns();
    if (t < next) return last;
    next = t + 1000000000ull;
    last = access(OFF_FILE, F_OK) == 0;
    return last;
}

// ------------------------------------------------------------------ overridability policy

static bool writable_page(uintptr_t addr) {
    vm_address_t a = (vm_address_t)addr;
    vm_size_t size = 0;
    vm_region_basic_info_data_64_t ri;
    mach_msg_type_number_t cnt = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t obj = MACH_PORT_NULL;
    if (vm_region_64(mach_task_self(), &a, &size, VM_REGION_BASIC_INFO_64, (vm_region_info_t)&ri, &cnt, &obj) != KERN_SUCCESS) return false;
    return a <= addr && addr < a + size && (ri.protection & VM_PROT_WRITE);
}

// unlock = true: swap in the table with CanOverride everywhere (idempotent). unlock = false: put the original back.
// Returns true when the table is in the requested state.
static bool policy_set(bool unlock) {
    bool ok = false;
    pthread_mutex_lock(&gOvrMu);
    CFDictionaryRef *slot = (CFDictionaryRef *)(G_OVRMAP + (uintptr_t)gSlide);
    CFDictionaryRef cur = *slot;
    if (!unlock) {
        if (gOvrPatched && cur == gOvrPatched && gOvrOrig) { *slot = gOvrOrig; info("overridability table restored"); }
        ok = true;
        goto done;
    }
    if (gOvrPatched && cur == gOvrPatched) { ok = true; goto done; }
    if (gOvrPatched && gOvrOrig && cur == gOvrOrig) { *slot = gOvrPatched; ok = true; goto done; }   // re-enabled after the kill switch
    if (gPolicyFailures >= 50) goto done;                       // stop retrying (the table never looked right)
    {
        CFTypeRef can = *(CFTypeRef *)(G_CAN_OVERRIDE + (uintptr_t)gSlide);
        CFTypeRef cannot = *(CFTypeRef *)(G_CANNOT_OVERRIDE + (uintptr_t)gSlide);
        if (!cf_is(cur, CFDictionaryGetTypeID()) || !cf_is(can, CFStringGetTypeID()) || !cf_is(cannot, CFStringGetTypeID()) ||
            CFDictionaryGetCount(cur) != 35 || !writable_page((uintptr_t)slot)) {
            if (++gPolicyFailures == 50) info("overridability table not recognised; leaving it alone");
            goto done;
        }
        const void *keys[35], *vals[35];
        CFDictionaryGetKeysAndValues(cur, keys, vals);
        int changed = 0;
        for (int i = 0; i < 35; i++) if (vals[i] && CFEqual(vals[i], cannot)) { vals[i] = can; changed++; }
        if (!changed) { ok = true; goto done; }
        CFDictionaryRef nd = CFDictionaryCreate(kCFAllocatorDefault, keys, vals, 35, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        if (!nd) goto done;
        gOvrOrig = (CFDictionaryRef)CFRetain(cur);
        gOvrPatched = nd;
        *slot = nd;                                              // single aligned pointer store
        ok = true;
        info("overridability table patched: %d of 35 categories now CanOverride", changed);
    }
done:
    pthread_mutex_unlock(&gOvrMu);
    return ok;
}

// ------------------------------------------------------------------ the ports that should be selectable

// Connected speaker ('pspk'), display ('pdsp') and wired headphone ('phpw') ports, read from the daemon's own
// connected-port list for Audio/Video/Default. Cached for 200 ms so a burst of picker queries costs one read.
typedef struct { uint64_t until; uint32_t ids[6]; int n; } WantCache;
static WantCache gWant;
static pthread_mutex_t gWantMu = PTHREAD_MUTEX_INITIALIZER;

static int wanted_ports(uint32_t out[6]) {
    int n = 0;
    pthread_mutex_lock(&gWantMu);
    uint64_t t = now_ns();
    if (t < gWant.until) {
        n = gWant.n;
        memcpy(out, gWant.ids, sizeof gWant.ids);
        pthread_mutex_unlock(&gWantMu);
        return n;
    }
    pthread_mutex_unlock(&gWantMu);

    CFArrayRef c = fn_conn(VAD_CAT_AV, VAD_MODE_DEFAULT, NULL, 0);
    uint32_t ids[6] = {0};
    if (cf_is(c, CFArrayGetTypeID())) {
        CFIndex cnt = CFArrayGetCount(c);
        for (CFIndex i = 0; i < cnt && i < 32 && n < 6; i++) {
            CFTypeRef e = CFArrayGetValueAtIndex(c, i);
            int32_t id = 0;
            if (is_cf_number(e) && CFNumberGetValue((CFNumberRef)e, kCFNumberSInt32Type, &id)) {
                uint32_t ty = fn_portType((uint32_t)id);
                if (ty == FOURCC('p', 's', 'p', 'k') || ty == FOURCC('p', 'd', 's', 'p') || ty == FOURCC('p', 'h', 'p', 'w')) ids[n++] = (uint32_t)id;
            }
        }
        CFRelease(c);
    }
    pthread_mutex_lock(&gWantMu);
    gWant.until = t + 200000000ull;
    gWant.n = n;
    memcpy(gWant.ids, ids, sizeof ids);
    pthread_mutex_unlock(&gWantMu);
    memcpy(out, ids, sizeof ids);
    return n;
}

// Returns a new +1 array to use instead of `r` (the caller then releases `r`), or NULL meaning "leave r alone".
static CFArrayRef ports_appended(CFTypeRef cat, CFTypeRef mode, CFArrayRef r, int *nadded) {
    *nadded = 0;
    CFIndex cnt = CFArrayGetCount(r);
    if (cnt < 1) return NULL;
    uint32_t want[6];
    int nwant = wanted_ports(want);
    if (nwant == 0) return NULL;

    CFMutableArrayRef m = NULL;
    CFTypeRef picked = NULL;
    bool pickedLoaded = false;
    for (int w = 0; w < nwant; w++) {
        bool present = false;
        for (CFIndex i = 0; i < cnt && !present; i++) present = dict_port_is(CFArrayGetValueAtIndex(r, i), want[w]);
        if (present) continue;

        CFTypeRef d = fn_mkDesc(want[w], 0, 0, 0, 0);            // same call form the daemon uses for port IDs
        if (!d) continue;
        if (!dict_port_is(d, want[w])) { CFRelease(d); continue; }
        CFMutableDictionaryRef md = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, (CFDictionaryRef)d);
        if (!m) m = CFArrayCreateMutableCopy(kCFAllocatorDefault, 0, r);
        if (md && m) {
            if (!pickedLoaded) {                                  // which route is the audio device actually using?
                pickedLoaded = true;
                if (fn_vadPicked) fn_vadPicked(cat, mode, NULL, NULL, &picked);
            }
            if (dict_port_is(picked, want[w])) CFDictionarySetValue(md, CFSTR("RouteCurrentlyPicked"), kCFBooleanTrue);
            CFArrayAppendValue(m, md);
            (*nadded)++;
        }
        if (md) CFRelease(md);
        CFRelease(d);
    }
    if (picked) CFRelease(picked);
    if (m && *nadded == 0) { CFRelease(m); m = NULL; }
    return m;
}

// Debug aid (only while DEBUG_FILE exists, checked at most once a second): log each distinct category/mode pair the
// first time it is seen, so a missing speaker row can be traced to the query that skipped it.
static bool debug_on(void) {
    static uint64_t next;
    static bool last;
    uint64_t t = now_ns();
    if (t < next) return last;
    next = t + 1000000000ull;
    last = access(DEBUG_FILE, F_OK) == 0;
    return last;
}

static void note_query(uintptr_t cat, uintptr_t mode, const char *what) {
    if (!debug_on()) return;
    char c[64] = "?", m[64] = "?";
    if (cf_is((CFTypeRef)cat, CFStringGetTypeID())) CFStringGetCString((CFStringRef)cat, c, sizeof c, kCFStringEncodingUTF8);
    if (cf_is((CFTypeRef)mode, CFStringGetTypeID())) CFStringGetCString((CFStringRef)mode, m, sizeof m, kCFStringEncodingUTF8);
    static char seen[16][130];
    static int nseen;
    char key[130];
    snprintf(key, sizeof key, "%s|%s|%s", c, m, what);
    for (int i = 0; i < nseen; i++) if (strcmp(seen[i], key) == 0) return;
    if (nseen < 16) strlcpy(seen[nseen++], key, sizeof seen[0]);
    dlog("query cat=%s mode=%s: %s", c, m, what);
}

// ------------------------------------------------------------------ the hook

// cmsmCopyPickableRoutesForRouteConfiguration(category, mode, a2, a3) -> +1 CFArray of route descriptions.
static uintptr_t hook_pick(ARGS8) {
    uintptr_t rv = orig_pick(PASS8);
    // Only the plain list for the picker: playback category (Audio/Video or MediaPlayback), any mode, no filters.
    // The mode is whatever the playing app's session uses: Default (YouTube), MoviePlayback (Netflix, most video
    // apps), SpokenAudio, ... Recording categories (PlayAndRecord_*) are not touched.
    if (a2 != 0) return rv;
    if (!(string_is((CFTypeRef)a0, CFSTR("Audio/Video")) || string_is((CFTypeRef)a0, CFSTR("MediaPlayback")))) { note_query(a0, a1, "other category"); return rv; }
    if (!cf_is((CFTypeRef)a1, CFStringGetTypeID())) return rv;
    if (a3 != 0 && !(cf_is((CFTypeRef)a3, CFArrayGetTypeID()) && CFArrayGetCount((CFArrayRef)a3) == 0)) return rv;
    if (!cf_is((CFTypeRef)rv, CFArrayGetTypeID())) return rv;
    note_query(a0, a1, "handled");

    if (killed()) { policy_set(false); return rv; }
    if (!policy_set(true)) { /* keep going: listing the rows is harmless without the policy change */ }

    int nadded = 0;
    CFIndex before = CFArrayGetCount((CFArrayRef)rv);
    CFArrayRef out = ports_appended((CFTypeRef)a0, (CFTypeRef)a1, (CFArrayRef)rv, &nadded);
    if (out) {
        CFRelease((CFTypeRef)rv);                                // the daemon's cached array keeps its own reference
        rv = (uintptr_t)out;
    }
    static volatile int lastAdded = -1;
    if (nadded != lastAdded) {                                    // log only when the outcome changes
        lastAdded = nadded;
        dlog("picker list %ld -> %ld routes (%d added)", (long)before, (long)(out ? CFArrayGetCount(out) : before), nadded);
    }
    return rv;
}

// ------------------------------------------------------------------ install / start-up

static bool gInstalled;

static void install(intptr_t slide) {
    if (gInstalled) return;
    gInstalled = true;
    gSlide = slide;
    if (!verify(&T_PICK) || !verify(&T_CONN) || !verify(&T_PTYPE) || !verify(&T_MKDESC) || !verify(&T_VADPK)) return;

    fn_portType = (uint32_t (*)(uint32_t))sign_fn(T_PTYPE.addr + (uintptr_t)slide);
    fn_conn     = (CFArrayRef (*)(uint32_t, uint32_t, CFTypeRef, int))sign_fn(T_CONN.addr + (uintptr_t)slide);
    fn_mkDesc   = (CFTypeRef (*)(uint32_t, uintptr_t, uintptr_t, uintptr_t, uintptr_t))sign_fn(T_MKDESC.addr + (uintptr_t)slide);
    fn_vadPicked = (void (*)(CFTypeRef, CFTypeRef, CFTypeRef, CFTypeRef, CFTypeRef *))sign_fn(T_VADPK.addr + (uintptr_t)slide);

    MSHookFunction(sign_fn(T_PICK.addr + (uintptr_t)slide), (void *)hook_pick, (void **)&orig_pick);
    if (!orig_pick) { info("hook installation failed"); return; }
    info("active (slide 0x%lx)", (long)slide);
    dlog("SpeakerPicker " TWEAK_VERSION " active");
}

static void image_added(const struct mach_header *mh, intptr_t slide) {
    Dl_info di;
    if (!dladdr(mh, &di) || !di.dli_fname) return;
    if (strcmp(di.dli_fname, MEDIAEXP_IMAGE) != 0) return;
    install(slide);
}

static bool os_build_ok(void) {
    char buf[64] = {0};
    size_t len = sizeof buf;
    if (sysctlbyname("kern.osversion", buf, &len, NULL, 0) != 0) return false;
    if (strcmp(buf, REQUIRED_OS_BUILD) != 0) { info("kern.osversion=%s (need %s); inactive", buf, REQUIRED_OS_BUILD); return false; }
    return true;
}

// Crash-loop guard: BOOT_FILE counts launches; it is removed once the daemon has stayed up STABLE_SECONDS.
// Touched only at launch.
static bool boot_guard_ok(void) {
    int strikes = 0;
    FILE *f = fopen(BOOT_FILE, "r");
    if (f) { if (fscanf(f, "%d", &strikes) != 1) strikes = 0; fclose(f); }
    if (strikes >= MAX_BOOT_STRIKES) {
        info("crash guard: %d short-lived launches in a row; inactive (delete %s to re-arm)", strikes, BOOT_FILE);
        return false;
    }
    f = fopen(BOOT_FILE, "w");
    if (f) { fprintf(f, "%d", strikes + 1); fclose(f); }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)STABLE_SECONDS * NSEC_PER_SEC),
                   dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ unlink(BOOT_FILE); });
    return true;
}

__attribute__((constructor))
static void speakerpicker_init(void) {
    const char *name = getprogname();
    if (!name || (strcmp(name, "audiomxd") != 0 && strcmp(name, "mediaserverd") != 0)) return;
    gLog = os_log_create("com.infernowolf19.speakerpicker", "main");
    if (access(OFF_FILE, F_OK) == 0) { info("kill switch present; inactive"); return; }
    if (!os_build_ok()) return;
    if (!boot_guard_ok()) return;
    _dyld_register_func_for_add_image(image_added);     // also fires for images that are already mapped
}
