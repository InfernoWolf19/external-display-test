// Shared between Tweak.x and the other Backport162 source files.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// Feature switches. Every feature is on by default (except the few marked opt-in in Tweak.x kOptIn);
// <jbroot>/tmp/Backport162.off.<name> turns one off and <jbroot>/tmp/Backport162.off turns everything off.
// Opt-in features need <jbroot>/tmp/Backport162.on.<name>. The names are in kFeatureNames (Tweak.x) and README.md.
// A package that checks sub-switches by name uses BP_OnName() / BP_OptInName() (same files, same kill switch).
enum {
    // group 4 (0.5.x)
    F_SCALE, F_AUTOHOST, F_BLANK, F_DISCONNECT, F_DISCSWITCH, F_ACTIVEDISPLAY, F_GESTUREGATE, F_LOCKEDPTR, F_NOWINDOW, F_DIRECTHOOK,
    // group 1b (modifier / event / response classes), group 1c (16.2 modifier rewrites), group 2 (layout data), group 2b (switcher view)
    F_G1B, F_G1B_APPTOAPP, F_G1C, F_G1C_PILES, F_G2, F_G2B, F_G2BPROTO, F_G2BLAYOUT, F_G2BKEYS, F_G2BAPERTURE, F_G2BTONGUE, F_CGREGION,
    // group 3 (plumbing)
    F_G3HANDLE, F_G3SNAPSHOT, F_G3TOPAFF, F_G3SWITCHER, F_G3CANVAS, F_G3EMBEDDED, F_G3BOOTORIENT,
    // group 3b (reconstruction)
    F_G3B_BANNER, F_G3B_MENU, F_G3B_PIP, F_G3B_KBWINDOW, F_G3B_STATUSBAR, F_G3B_ORIENT, F_G3B_GRID, F_G3B_GUIDE, F_G3B_SPLIT, F_G3B_PREFLIGHTLOG, F_G3B_AXROLES,
    // group 4b (reconstruction)
    F_CLONEMIRROR, F_EDU, F_EDUNATIVE, F_PRESUBSET, F_DEFERACT, F_LOCKEDPTR2, F_MIGRATE, F_FOCUSLOCK, F_ARRANGE, F_METHODOLOGY0,
    // group 3c (top-affordance Zoom on a full-screen app)
    F_G3C,
    F_COUNT
};

BOOL BP_On(int feature);
BOOL BP_OnName(const char *name);       // default-on switch by name: not killed and no Backport162.off.<name>
BOOL BP_OptInName(const char *name);    // opt-in switch by name: BP_OnName(name) and Backport162.on.<name> exists
void BP_Log(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);
// Always-on anomaly channel: appends `ANOMALY <tag>: <message>` to Backport162.log even without Backport162.debug. For a ported body whose assumption failed and that silently
// answers the stock / default value: a missing selector / class / ivar, a value of an unexpected type, a fallback to the 16.0 answer where 16.2 has none.  De-duplicated per
// (tag, message), at most 8 formats per (tag, format string), 40 lines per tag and 300 per process, so it is safe on hot paths (nothing is formatted once a condition is known).
void BP_Anomaly(const char *tag, NSString *fmt, ...) NS_FORMAT_FUNCTION(2, 3);
BOOL BP_LogEnabled(void);               // cheap test (cached one second): lets callers skip building log arguments

// Object ivar access that cannot mistake a scalar ivar for an object (object_getIvar on a BOOL / NSInteger / struct-sized ivar returns the raw bits as an
// "object" and ARC then retains them: SIGSEGV in objc_retain). Both return nil / do nothing unless the ivar exists and is an object, class or block.
// Ivar lookup by name that is never silent: an ivar that does not exist (a different layout in this build, a class that is not the one the port assumed) reads as nil / 0 / NO in every
// caller, so the miss is announced once per (class, name) through BP_Anomaly("ivar"). Nil class (nil receiver) is a legitimate absence and stays quiet.
static inline Ivar BP_IvarLookup(Class cls, const char *name) {
    Ivar iv = cls ? class_getInstanceVariable(cls, name) : NULL;
    if (!iv && cls) {
        static uintptr_t seen[512];
        uintptr_t key = (((uintptr_t)(__bridge void *)cls * 31) ^ ((uintptr_t)name * 131)) | 1;
        for (int k = 0; k < 512; k++) {
            uintptr_t cur = __atomic_load_n(&seen[k], __ATOMIC_RELAXED);
            if (cur == key) return iv;
            if (cur == 0) { uintptr_t z = 0; if (__atomic_compare_exchange_n(&seen[k], &z, key, 0, __ATOMIC_RELAXED, __ATOMIC_RELAXED)) break; if (z == key) return iv; }
        }
        BP_Anomaly("ivar", @"ivar %s is missing on %s: every read of it answers nil / 0 / NO", name, class_getName(cls));
    }
    return iv;
}
// Selector miss of the typed send helpers (BPX_*, G1B_Send*, G1C_Resp, ...): the receiver exists but does not implement the selector, so the helper answers nil / 0 / NO. One line per
// (tag, class, selector).  A nil receiver is a legitimate absence and is not reported.
static inline void BP_SelMiss(const char *tag, id o, SEL s) {
    static uintptr_t seen[1024];
    Class k = object_getClass(o);
    uintptr_t key = (((uintptr_t)(__bridge void *)k * 31) ^ ((uintptr_t)(void *)s * 131) ^ ((uintptr_t)tag * 7)) | 1;
    for (int i = 0; i < 1024; i++) {
        uintptr_t cur = __atomic_load_n(&seen[i], __ATOMIC_RELAXED);
        if (cur == key) return;
        if (cur == 0) { uintptr_t z = 0; if (__atomic_compare_exchange_n(&seen[i], &z, key, 0, __ATOMIC_RELAXED, __ATOMIC_RELAXED)) break; if (z == key) return; }
    }
    BP_Anomaly(tag, @"-[%s %s] is not implemented by the receiver: the helper answers nil / 0 / NO", class_getName(k), sel_getName(s));
}
static inline BOOL BP_IvarIsObj(Ivar iv) {
    const char *e = iv ? ivar_getTypeEncoding(iv) : NULL;
    return e && (e[0] == '@' || e[0] == '#');
}
static inline id BP_ObjIvar(id o, Ivar iv) {
    if (o && iv && !BP_IvarIsObj(iv)) BP_Anomaly("ivar-type", @"ivar %s of %s is not an object (type %s): read as nil", ivar_getName(iv), class_getName(object_getClass(o)), ivar_getTypeEncoding(iv) ?: "?");
    return (o && BP_IvarIsObj(iv)) ? object_getIvar(o, iv) : nil;
}
static inline void BP_SetObjIvar(id o, Ivar iv, id v) { if (o && BP_IvarIsObj(iv)) object_setIvar(o, iv, v); }

// Type gate that is never silent: YES when `v` is an instance of `Cls`; a NON-nil value of another class (the 16.2 contract returned a collection of another kind than the port assumed, the
// NSArray-only gate that dropped the dragged layouts of 0efa07d was exactly that) is announced once through BP_Anomaly before the caller takes its default path.  nil is a legitimate "absent".
#define BP_KIND(tag, v, Cls) ({ id _bp_v = (v); BOOL _bp_ok = [_bp_v isKindOfClass:[Cls class]]; \
    if (!_bp_ok && _bp_v) BP_Anomaly(tag, @"%s is a %@, expected %s: the default path is taken", #v, NSStringFromClass(object_getClass(_bp_v)), #Cls); _bp_ok; })
// Any collection as an NSArray (NSArray, NSOrderedSet, NSSet / NSMutableSet / NSCountedSet in unspecified order); nil for anything else.
static inline NSArray *BP_AsArray(id o) {
    if ([o isKindOfClass:[NSArray class]]) return o;
    if ([o isKindOfClass:[NSOrderedSet class]]) return [(NSOrderedSet *)o array];
    if ([o isKindOfClass:[NSSet class]]) return [(NSSet *)o allObjects];
    return nil;
}

