// liftdev.h : device side of the C code a2c.py generates (see liftcommon.h): selectors, classes, ivar offsets, C symbols, typed calls with the
// full register file (x0..x7 + d0..d7 are always passed, which is exactly what the arm64 ABI hands to any callee; the return kind is chosen per
// call site by a2c.py from the instructions that follow the call), and the ARC runtime entry points.
// Plain C and NO Objective-C headers: the generated files are compiled without ARC and call objc_retain / objc_release exactly where the
// machine code does, so every runtime function is declared here under a private name bound to the real symbol by an asm label (no clash
// with objc-arc.h declarations, which differ between SDKs).
#ifndef BP_LIFTDEV_H
#define BP_LIFTDEV_H
#include "liftcommon.h"
#include <dlfcn.h>
#include <stddef.h>

extern void *lift_sel_registerName(const char *) __asm__("_sel_registerName");
extern void *lift_objc_getClass(const char *) __asm__("_objc_getClass");
extern void *lift_class_getInstanceVariable(void *, const char *) __asm__("_class_getInstanceVariable");
extern ptrdiff_t lift_ivar_getOffset(void *) __asm__("_ivar_getOffset");
extern void lift_objc_msgSend(void) __asm__("_objc_msgSend");
extern void *lift_objc_retain(void *) __asm__("_objc_retain");
extern void lift_objc_release(void *) __asm__("_objc_release");
extern void *lift_objc_retainAutoreleasedReturnValue(void *) __asm__("_objc_retainAutoreleasedReturnValue");
extern void *lift_objc_unsafeClaimAutoreleasedReturnValue(void *) __asm__("_objc_unsafeClaimAutoreleasedReturnValue");
extern void *lift_objc_autorelease(void *) __asm__("_objc_autorelease");
extern void *lift_objc_retainAutorelease(void *) __asm__("_objc_retainAutorelease");
extern void *lift_objc_autoreleaseReturnValue(void *) __asm__("_objc_autoreleaseReturnValue");
extern void *lift_objc_retainAutoreleaseReturnValue(void *) __asm__("_objc_retainAutoreleaseReturnValue");
extern void lift_objc_storeStrong(void **, void *) __asm__("_objc_storeStrong");
extern void lift_objc_enumerationMutation(void *) __asm__("_objc_enumerationMutation");
extern void lift_stack_chk_fail(void) __asm__("___stack_chk_fail");

#define SEL(t, i) lift_sel_registerName((t)[i])
#define CLS(t, i) lift_objc_getClass((t)[i])
static inline void *lift_gsym(const char *n) { if (*n == '_') n++; return dlsym(RTLD_DEFAULT, n); }
#define GSYM(t, i) lift_gsym((t)[i])
#define CFSTR_(t, i) lift_cfstr((t)[i])
extern void *lift_cfstr(const char *utf8);   // provided by the includer's .m / .x side (an NSString constant): see Y34 files
static inline long lift_ivoff(const char *spec) {
    char cls[96]; const char *dot = strchr(spec, '.');
    if (!dot || (size_t)(dot - spec) >= sizeof cls) return -1;
    memcpy(cls, spec, (size_t)(dot - spec)); cls[dot - spec] = 0;
    void *c = lift_objc_getClass(cls); if (!c) return -1;
    void *iv = lift_class_getInstanceVariable(c, dot + 1); if (!iv) return -1;
    return (long)lift_ivar_getOffset(iv);
}
#define IVOFF(t, i) lift_ivoff((t)[i])
// first name the includer cannot resolve (NULL = everything resolves); checked once at install time, a function with a miss is NOT installed
static inline const char *lift_preflight(const char *const *fns, int nf, const char *const *cls, int nc, const char *const *ivs, int ni) {
    for (int k = 0; k < nf; k++) if (fns[k] && !lift_gsym(fns[k])) return fns[k];
    for (int k = 0; k < nc; k++) if (cls[k] && !lift_objc_getClass(cls[k])) return cls[k];
    for (int k = 0; k < ni; k++) if (ivs[k] && lift_ivoff(ivs[k]) < 0) return ivs[k];
    return 0;
}
#define LIFT_PREFLIGHT(f, c, i) lift_preflight((f), (int)(sizeof(f) / sizeof((f)[0])), (c), (int)(sizeof(c) / sizeof((c)[0])), (i), (int)(sizeof(i) / sizeof((i)[0])))

// typed calls: ints x0..x7, doubles d0..d7 (VR[n][0] is the low half of vn)
#define LIFT_ARGS X[0], X[1], X[2], X[3], X[4], X[5], X[6], X[7], FD(VR[0][0]), FD(VR[1][0]), FD(VR[2][0]), FD(VR[3][0]), FD(VR[4][0]), FD(VR[5][0]), FD(VR[6][0]), FD(VR[7][0])
#define LIFT_PARAMS uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, double, double, double, double, double, double, double, double
#define LIFT_CALL_x(fn) do { X[0] = ((uint64_t (*)(LIFT_PARAMS))(fn))(LIFT_ARGS); } while (0)
#define LIFT_CALL_v(fn) do { ((void (*)(LIFT_PARAMS))(fn))(LIFT_ARGS); } while (0)
#define LIFT_CALL_d(fn) do { double r_ = ((double (*)(LIFT_PARAMS))(fn))(LIFT_ARGS); VR[0][0] = DB(r_); VR[0][1] = 0; } while (0)
#define LIFT_CALL_size(fn) do { LiftSize r_ = ((LiftSize (*)(LIFT_PARAMS))(fn))(LIFT_ARGS); VR[0][0] = DB(r_.w); VR[1][0] = DB(r_.h); VR[0][1] = VR[1][1] = 0; } while (0)
#define LIFT_CALL_rect(fn) do { LiftRect r_ = ((LiftRect (*)(LIFT_PARAMS))(fn))(LIFT_ARGS); VR[0][0] = DB(r_.x); VR[1][0] = DB(r_.y); VR[2][0] = DB(r_.w); VR[3][0] = DB(r_.h); VR[0][1] = VR[1][1] = VR[2][1] = VR[3][1] = 0; } while (0)
#define CALLMSG(kind) LIFT_CALL_##kind((void *)lift_objc_msgSend)
#define CALLFN(t, i, kind) do { void *f_ = lift_gsym((t)[i]); if (f_) LIFT_CALL_##kind(f_); } while (0)

#define RT_RETAIN(p) lift_objc_retain(p)
#define RT_RELEASE(p) lift_objc_release(p)
#define RT_CLAIM(p) lift_objc_retainAutoreleasedReturnValue(p)
#define RT_UNSAFECLAIM(p) lift_objc_unsafeClaimAutoreleasedReturnValue(p)
#define RT_AUTORELEASE(p) lift_objc_autorelease(p)
#define RT_RETAINAUTORELEASE(p) lift_objc_retainAutorelease(p)
#define RT_AUTORELEASERV(p) lift_objc_autoreleaseReturnValue(p)
#define RT_RETAINAUTORELEASERV(p) lift_objc_retainAutoreleaseReturnValue(p)
#define RT_STORESTRONG(a, b) lift_objc_storeStrong((a), (b))
#define RT_ENUMMUT(p) lift_objc_enumerationMutation(p)
#define STACKFAIL() lift_stack_chk_fail()
#endif
