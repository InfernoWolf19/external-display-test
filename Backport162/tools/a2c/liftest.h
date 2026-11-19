// liftest.h : Linux test harness side of the generated code (see liftcommon.h).  Every call / selector / ivar goes to a python callback, so
// the lifted function can be compared with the Unicorn emulation of the original machine code on the same modelled environment.
#ifndef BP_LIFTEST_H
#define BP_LIFTEST_H
#define LIFT_TEST_HOOKS 1
#define LIFT_BSS            /* the mutable statics of the 16.2 image are visible to the harness: it zeroes them before every run (the emulated .bss is fresh) */
#include <stdio.h>
#include "liftcommon.h"
typedef void (*lift_cb_t)(int isMsg, const char *name, uint64_t *X, uint64_t (*VR)[2]);
typedef long (*lift_iv_t)(const char *name);
static lift_cb_t lift_cb; static lift_iv_t lift_iv;
uint64_t lift_sp0;
#define LIFT_ENTRY() (lift_sp0 = X[31])
void lift_set(lift_cb_t cb, lift_iv_t iv) { lift_cb = cb; lift_iv = iv; }
#define SEL(t, i) ((void *)(t)[i])
#define CLS(t, i) ((void *)(t)[i])
// the address of a C symbol: a cell that holds a marker (the name), so that a load through the address (a data symbol like kCAFilterBox) reads a well defined value
uint64_t lift_cells[64][2]; int lift_ncells;
static inline void *lift_gcell(const char *nm) { for (int i = 0; i < lift_ncells; i++) if (lift_cells[i][1] == (uint64_t)(uintptr_t)nm) return &lift_cells[i][0]; lift_cells[lift_ncells][0] = (uint64_t)(uintptr_t)nm; lift_cells[lift_ncells][1] = (uint64_t)(uintptr_t)nm; return &lift_cells[lift_ncells++][0]; }
#define GSYM(t, i) lift_gcell((t)[i])
// a CFString constant: a pointer of its own (a string literal identical to a selector name must not share the selector's address)
char *lift_cfs_tab[256]; int lift_ncfs;
static inline void *lift_cfs(const char *s) { for (int i = 0; i < lift_ncfs; i++) if (strcmp(lift_cfs_tab[i], s) == 0) return lift_cfs_tab[i]; lift_cfs_tab[lift_ncfs] = strdup(s); return lift_cfs_tab[lift_ncfs++]; }
#define CFSTR_(t, i) lift_cfs((t)[i])
#define IVOFF(t, i) lift_iv((t)[i])
const char *lift_kind;
const char *lift_cstrs[256]; int lift_ncstr;
static inline const char *lift_cstr(const char *s) { for (int i = 0; i < lift_ncstr; i++) if (lift_cstrs[i] == s) return s; if (lift_ncstr < 256) lift_cstrs[lift_ncstr++] = s; return s; }
#define LIFT_CSTR(s) lift_cstr(s)
#define LIFT_DSO() ((void *)(uintptr_t)0xd50d50ull)
#define LIFT_STKINIT(p) memset((p), 0, sizeof (p))
// ownership / PAC / block events: the python side compares them with the Unicorn emulation of the original (count and order)
typedef void (*lift_ev_t)(const char *what, uint64_t a, uint64_t b);
static lift_ev_t lift_evcb;
void lift_set_ev(lift_ev_t e) { lift_evcb = e; }
#define LIFT_EV(w, a, b) ((void)(lift_evcb ? (lift_evcb((w), (uint64_t)(a), (uint64_t)(b)), 0) : 0))
static inline uint64_t lift_ev_pac(const char *w, int key, uint64_t p, uint64_t m) { static const char *const n[2][4] = {{"pacia", "pacib", "pacda", "pacdb"}, {"autia", "autib", "autda", "autdb"}}; if (lift_evcb) lift_evcb(n[w[0] == 'a'][key], p, m); return p; }
#define LIFT_PAC(key, p, m) lift_ev_pac("p", (key), (uint64_t)(p), (uint64_t)(m))
#define LIFT_AUT(key, p, m) lift_ev_pac("a", (key), (uint64_t)(p), (uint64_t)(m))
#define LIFT_STRIP(p) ((uint64_t)(p))
uint64_t lift_fnaddrs[16][2]; const char *lift_fnnames[16]; int lift_nfn;
static inline uint64_t lift_fnaddr(void *fn, const char *nm) { for (int i = 0; i < lift_nfn; i++) if (lift_fnaddrs[i][0] == (uint64_t)(uintptr_t)fn) return (uint64_t)(uintptr_t)fn; lift_fnaddrs[lift_nfn][0] = (uint64_t)(uintptr_t)fn; lift_fnnames[lift_nfn++] = nm; return (uint64_t)(uintptr_t)fn; }
#define LIFT_FNADDR(fn) lift_fnaddr((void *)(fn), #fn)
#define LIFT_CALLPTR(p, key, m) ((void *)(uintptr_t)(p))
static char lift_pn[64];
static inline const char *lift_ptrname(void *p) { for (int i = 0; i < lift_nfn; i++) if (lift_fnaddrs[i][0] == (uint64_t)(uintptr_t)p) { snprintf(lift_pn, sizeof lift_pn, "L:%s", lift_fnnames[i]); return lift_pn; } return "indirect"; }
uint64_t lift_descs[16][3]; int lift_ndesc;
static inline uint64_t *lift_desc(uint64_t *p, const char *sig, uint64_t size) { for (int i = 0; i < lift_ndesc; i++) if (lift_descs[i][0] == (uint64_t)(uintptr_t)p) return p; lift_descs[lift_ndesc][0] = (uint64_t)(uintptr_t)p; lift_descs[lift_ndesc][1] = (uint64_t)(uintptr_t)sig; lift_descs[lift_ndesc++][2] = size; return p; }
#define LIFT_DESC(p, sig, size) lift_desc((p), (sig), (size))
#define CALLLOCAL(fn, kind) (lift_kind = #kind, lift_cb(0, "L:" #fn, X, VR))
#define CALLPTR(fn, kind) (lift_kind = #kind, lift_cb(0, lift_ptrname((void *)(fn)), X, VR))
#define CALLMSG(kind) (lift_kind = #kind, lift_cb(1, (const char *)(uintptr_t)X[1], X, VR))
#define CALLFN(t, i, kind) (lift_kind = #kind, lift_cb(0, (t)[i], X, VR))
#define LIFT_PREFLIGHT(f, c, i) ((const char *)0)
#define RT_RETAIN(p) (LIFT_EV("retain", (p), 0), (p))
#define RT_RELEASE(p) LIFT_EV("release", (p), 0)
#define RT_CLAIM(p) (LIFT_EV("claim", (p), 0), (p))
#define RT_UNSAFECLAIM(p) (LIFT_EV("unsafeclaim", (p), 0), (p))
#define RT_AUTORELEASE(p) (LIFT_EV("autorelease", (p), 0), (p))
#define RT_RETAINAUTORELEASE(p) (LIFT_EV("retainAutorelease", (p), 0), (p))
#define RT_AUTORELEASERV(p) (LIFT_EV("autoreleaseRV", (p), 0), (p))
#define RT_RETAINAUTORELEASERV(p) (LIFT_EV("retainAutoreleaseRV", (p), 0), (p))
#define RT_STORESTRONG(a, b) do { LIFT_EV("storeStrong", (a), (b)); *(void **)(a) = (b); } while (0)
#define RT_ENUMMUT(p) lift_cb(0, "objc_enumerationMutation", X, VR)
#define STACKFAIL() lift_cb(0, "___stack_chk_fail", X, VR)
#endif
