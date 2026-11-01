// liftest.h : Linux test harness side of the generated code (see liftcommon.h).  Every call / selector / ivar goes to a python callback, so
// the lifted function can be compared with the Unicorn emulation of the original machine code on the same modelled environment.
#ifndef BP_LIFTEST_H
#define BP_LIFTEST_H
#include "liftcommon.h"
typedef void (*lift_cb_t)(int isMsg, const char *name, uint64_t *X, uint64_t (*VR)[2]);
typedef long (*lift_iv_t)(const char *name);
static lift_cb_t lift_cb; static lift_iv_t lift_iv;
void lift_set(lift_cb_t cb, lift_iv_t iv) { lift_cb = cb; lift_iv = iv; }
#define SEL(t, i) ((void *)(t)[i])
#define CLS(t, i) ((void *)(t)[i])
#define GSYM(t, i) ((void *)(t)[i])
#define CFSTR_(t, i) ((void *)(t)[i])
#define IVOFF(t, i) lift_iv((t)[i])
#define CALLMSG(kind) lift_cb(1, (const char *)(uintptr_t)X[1], X, VR)
#define CALLFN(t, i, kind) lift_cb(0, (t)[i], X, VR)
#define LIFT_PREFLIGHT(f, c, i) ((const char *)0)
#define RT_RETAIN(p) (p)
#define RT_RELEASE(p) ((void)(p))
#define RT_CLAIM(p) (p)
#define RT_UNSAFECLAIM(p) (p)
#define RT_AUTORELEASE(p) (p)
#define RT_RETAINAUTORELEASE(p) (p)
#define RT_AUTORELEASERV(p) (p)
#define RT_RETAINAUTORELEASERV(p) (p)
#define RT_STORESTRONG(a, b) do { *(void **)(a) = (b); } while (0)
#define RT_ENUMMUT(p) lift_cb(0, "objc_enumerationMutation", X, VR)
#define STACKFAIL() lift_cb(0, "___stack_chk_fail", X, VR)
#endif
