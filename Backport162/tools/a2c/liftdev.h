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

#define LIFT_ENTRY() ((void)0)
#define LIFT_STKINIT(p) ((void)0)
#define SEL(t, i) lift_sel_registerName((t)[i])
// class and ivar lookups go through Y34LiftRT.c: a runtime SUBCLASS registered for a 16.2 class (lift_register_ext) that carries the ivars 16.0 lacks is returned for the
// class name (so recompiled code allocates it) and is searched first for an ivar offset
extern void *lift_class_lookup(const char *name);
extern long lift_ivoff_lookup(const char *spec);
extern void lift_register_ext(const char *baseName, void *extClass);
#define CLS(t, i) lift_class_lookup((t)[i])
// C functions of the 16.2 frameworks that 16.0 does not export (BSSizeSwap, SBFIsChamoisWindowingUIAvailable): tiny C re-implementations in Y34LiftRT.c, used only when dlsym finds nothing
extern void *lift_builtin(const char *bareName);
static inline void *lift_gsym(const char *n) { if (*n == '_') n++; void *p = dlsym(RTLD_DEFAULT, n); return p ? p : lift_builtin(n); }
#define GSYM(t, i) lift_gsym((t)[i])
#define CFSTR_(t, i) lift_cfstr((t)[i])
extern void *lift_cfstr(const char *utf8);   // provided by the includer's .m / .x side (an NSString constant): see Y34ClassicTypes.x
#define IVOFF(t, i) lift_ivoff_lookup((t)[i])
// EVERY name the process cannot resolve, comma separated in a static buffer (NULL = everything resolves); checked once at install time, a function with a miss is NOT installed
static inline const char *lift_preflight(const char *const *fns, int nf, const char *const *cls, int nc, const char *const *ivs, int ni) {
    static char buf[512]; size_t n = 0; buf[0] = 0;
#define LIFT_PF_ADD(s) do { size_t l_ = strlen(s); if (n + l_ + 2 < sizeof buf) { if (n) buf[n++] = ','; memcpy(buf + n, (s), l_); n += l_; buf[n] = 0; } } while (0)
    for (int k = 0; k < nf; k++) if (fns[k] && !lift_gsym(fns[k])) LIFT_PF_ADD(fns[k]);
    for (int k = 0; k < nc; k++) if (cls[k] && !lift_class_lookup(cls[k])) LIFT_PF_ADD(cls[k]);
    for (int k = 0; k < ni; k++) if (ivs[k] && lift_ivoff_lookup(ivs[k]) < 0) LIFT_PF_ADD(ivs[k]);
    return n ? buf : 0;
}
#define LIFT_PREFLIGHT(f, c, i) lift_preflight((f), (int)(sizeof(f) / sizeof((f)[0])), (c), (int)(sizeof(c) / sizeof((c)[0])), (i), (int)(sizeof(i) / sizeof((i)[0])))

// typed calls: ints x0..x7, doubles d0..d7 (VR[n][0] is the low half of vn)
// the 12 words at sp are passed as stack arguments: the memory image the machine code built at [sp, #0 ..] IS the stack argument area of the callee (Darwin packs small arguments, the image keeps that packing)
#define LIFT_STK(k) LD64(X[31] + 8 * (k))
#define LIFT_ARGS X[0], X[1], X[2], X[3], X[4], X[5], X[6], X[7], FD(VR[0][0]), FD(VR[1][0]), FD(VR[2][0]), FD(VR[3][0]), FD(VR[4][0]), FD(VR[5][0]), FD(VR[6][0]), FD(VR[7][0]), \
    LIFT_STK(0), LIFT_STK(1), LIFT_STK(2), LIFT_STK(3), LIFT_STK(4), LIFT_STK(5), LIFT_STK(6), LIFT_STK(7), LIFT_STK(8), LIFT_STK(9), LIFT_STK(10), LIFT_STK(11)
#define LIFT_PARAMS uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, double, double, double, double, double, double, double, double, \
    uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t
#define LIFT_CALL_x(fn) do { X[0] = ((uint64_t (*)(LIFT_PARAMS))(fn))(LIFT_ARGS); } while (0)
#define LIFT_CALL_v(fn) do { ((void (*)(LIFT_PARAMS))(fn))(LIFT_ARGS); } while (0)
#define LIFT_CALL_d(fn) do { double r_ = ((double (*)(LIFT_PARAMS))(fn))(LIFT_ARGS); VR[0][0] = DB(r_); VR[0][1] = 0; } while (0)
#define LIFT_CALL_size(fn) do { LiftSize r_ = ((LiftSize (*)(LIFT_PARAMS))(fn))(LIFT_ARGS); VR[0][0] = DB(r_.w); VR[1][0] = DB(r_.h); VR[0][1] = VR[1][1] = 0; } while (0)
#define LIFT_CALL_rect(fn) do { LiftRect r_ = ((LiftRect (*)(LIFT_PARAMS))(fn))(LIFT_ARGS); VR[0][0] = DB(r_.x); VR[1][0] = DB(r_.y); VR[2][0] = DB(r_.w); VR[3][0] = DB(r_.h); VR[0][1] = VR[1][1] = VR[2][1] = VR[3][1] = 0; } while (0)
// indirect results (x8): the callee writes the struct through the hidden pointer; the typed pointer returns a struct of that size so the compiler passes x8 itself
typedef struct { uint8_t b[48]; } LiftM48;
typedef struct { uint8_t b[128]; } LiftM128;
#define LIFT_CALL_m48(fn) do { LiftM48 r_ = ((LiftM48 (*)(LIFT_PARAMS))(fn))(LIFT_ARGS); memcpy((void *)(uintptr_t)X[8], &r_, sizeof r_); } while (0)
#define LIFT_CALL_m128(fn) do { LiftM128 r_ = ((LiftM128 (*)(LIFT_PARAMS))(fn))(LIFT_ARGS); memcpy((void *)(uintptr_t)X[8], &r_, sizeof r_); } while (0)
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
