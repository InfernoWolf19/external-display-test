// Y17Common.h : helpers of the second delta-sweep pass (Y17 .. Y2x): logged guards.  Header only, static inline.
// Rule of the pass: a helper never silently returns NO / nil for a missing selector, class or ivar: the first miss per (tag, class, selector) is logged (always, BP_Anomaly), later ones are dropped.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "BPY.h"

static inline uint64_t Y17_Fnv(const char *s, uint64_t h) { for (; *s; s++) { h ^= (unsigned char)*s; h *= 1099511628211ull; } return h; }
// The first miss per (tag, class, selector) is written to Backport162.log as `ANOMALY <tag>: GUARD(<tag>) ...` ALWAYS (BP_Anomaly, no Backport162.debug needed); repeats cost a hash and a table
// probe (no allocation): this runs on hot paths (every touch / frame of a hook whose selector is missing).
static inline void Y17_GuardOnce(const char *tag, id obj, const char *what) {
    static uint64_t seen[512];
    const char *cn = obj ? class_getName(object_getClass(obj)) : "nil";
    uint64_t h = (Y17_Fnv(tag, 14695981039346656037ull) ^ (Y17_Fnv(cn, 1469598103934665603ull) * 31) ^ (Y17_Fnv(what, 1099511628211ull) * 131)) | 1;
    for (size_t k = 0; k < 8; k++) {
        uint64_t *e = &seen[(h + k) % 512];
        uint64_t cur = __atomic_load_n(e, __ATOMIC_RELAXED);
        if (cur == h) return;
        if (cur == 0) {
            uint64_t zero = 0;
            if (__atomic_compare_exchange_n(e, &zero, h, 0, __ATOMIC_RELAXED, __ATOMIC_RELAXED)) { BP_Anomaly(tag, @"GUARD(%s) %s missing on %s (logged once)", tag, what, cn); return; }
            if (zero == h) return;
        }
    }
}
// object message with a logged guard
static inline id Y17_Obj0(const char *tag, id o, const char *sel) {
    if (!o || ![o respondsToSelector:sel_registerName(sel)]) { Y17_GuardOnce(tag, o, sel); return nil; }
    return ((id (*)(id, SEL))objc_msgSend)(o, sel_registerName(sel));
}
static inline id Y17_Obj1(const char *tag, id o, const char *sel, id a) {
    if (!o || ![o respondsToSelector:sel_registerName(sel)]) { Y17_GuardOnce(tag, o, sel); return nil; }
    return ((id (*)(id, SEL, id))objc_msgSend)(o, sel_registerName(sel), a);
}
// 16.2 FBDisplayManager configurationForIdentity: scale of the display of an identity (0 when unknown, logged)
static inline double Y17_ScaleForIdentity(const char *tag, id identity) {
    Class fb = NSClassFromString(@"FBDisplayManager");
    id mgr = Y17_Obj0(tag, (id)fb, "sharedInstance");
    id cfg = Y17_Obj1(tag, mgr, "configurationForIdentity:", identity);
    if (!cfg || ![cfg respondsToSelector:sel_registerName("scale")]) { Y17_GuardOnce(tag, cfg, "scale"); return 0; }
    return ((double (*)(id, SEL))objc_msgSend)(cfg, sel_registerName("scale"));
}
static inline long long Y17_LL1(id o, const char *sel, id a) {
    SEL s = sel_registerName(sel);
    if (!o) return 0;
    if (![o respondsToSelector:s]) { BP_SelMiss("sel-y17", o, s); return 0; }
    return ((long long (*)(id, SEL, id))objc_msgSend)(o, s, a);
}
