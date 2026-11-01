// liftcommon.h : shared C macros of the code a2c.py generates (static recompilation of arm64e machine code of the 16.2 SpringBoard / UIKit
// into C).  The generated function keeps the register file (X, VR), the flags (N Z C V) and the stack frame (stk_) as C variables, so one
// machine instruction is one C statement; only memory, calls and the Objective-C runtime hooks (ivar offsets, selectors, classes) come
// from the includer (liftdev.h on the device, liftest.h in the Linux test harness).
#ifndef BP_LIFTCOMMON_H
#define BP_LIFTCOMMON_H
#pragma clang diagnostic ignored "-Wunused-label"
#pragma clang diagnostic ignored "-Wunused-variable"
#pragma clang diagnostic ignored "-Wunused-but-set-variable"
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wunused-value"
#include <stdint.h>
#include <string.h>
#include <math.h>

static uint64_t lift_guard_cell = 0x5a17c0de5a17c0deull;
typedef struct { double w, h; } LiftSize;
typedef struct { double x, y, w, h; } LiftRect;

static inline uint64_t lift_ld(uint64_t a, int n) { uint64_t v = 0; memcpy(&v, (const void *)(uintptr_t)a, n); return v; }
static inline void lift_st(uint64_t a, uint64_t v, int n) { memcpy((void *)(uintptr_t)a, &v, n); }
#define LD8(a) lift_ld((a), 1)
#define LD16(a) lift_ld((a), 2)
#define LD32(a) lift_ld((a), 4)
#define LD64(a) lift_ld((a), 8)
#define ST8(a, v) lift_st((a), (uint64_t)(v), 1)
#define ST16(a, v) lift_st((a), (uint64_t)(v), 2)
#define ST32(a, v) lift_st((a), (uint64_t)(v), 4)
#define ST64(a, v) lift_st((a), (uint64_t)(v), 8)

static inline double lift_fd(uint64_t b) { double d; memcpy(&d, &b, 8); return d; }
static inline uint64_t lift_db(double d) { uint64_t b; memcpy(&b, &d, 8); return b; }
static inline float lift_fs(uint64_t b) { uint32_t w = (uint32_t)b; float f; memcpy(&f, &w, 4); return f; }
static inline uint64_t lift_sb(float f) { uint32_t w; memcpy(&w, &f, 4); return w; }
#define FD(b) lift_fd(b)
#define DB(d) lift_db(d)
#define FS(b) lift_fs(b)
#define SB(f) lift_sb(f)

// fcmp: unordered N=0 Z=0 C=1 V=1, equal 0110, less 1000, greater 0010
#define FCMP(a, b) do { double a_ = (a), b_ = (b); if (a_ != a_ || b_ != b_) { N = 0; Z = 0; C = 1; V = 1; } else if (a_ == b_) { N = 0; Z = 1; C = 1; V = 0; } else if (a_ < b_) { N = 1; Z = 0; C = 0; V = 0; } else { N = 0; Z = 0; C = 1; V = 0; } } while (0)
static inline double lift_fmax(double a, double b) { return (a != a || b != b) ? NAN : (a > b ? a : b); }
static inline double lift_fmin(double a, double b) { return (a != a || b != b) ? NAN : (a < b ? a : b); }
#define FMAXF_(a, b) lift_fmax((a), (b))
#define FMINF_(a, b) lift_fmin((a), (b))
#define FMA_(a, b, c) fma((a), (b), (c))
static inline uint64_t lift_cvts64(double d) { if (d != d) return 0; if (d >= 9223372036854775808.0) return 0x7fffffffffffffffull; if (d <= -9223372036854775808.0) return 0x8000000000000000ull; return (uint64_t)(int64_t)d; }
static inline uint64_t lift_cvts32(double d) { if (d != d) return 0; if (d >= 2147483648.0) return 0x7fffffffu; if (d <= -2147483649.0) return 0x80000000u; return (uint32_t)(int32_t)d; }
static inline uint64_t lift_cvtu(double d) { if (d != d || d <= 0) return 0; if (d >= 18446744073709551616.0) return ~0ull; return (uint64_t)d; }
#define CVTS64(d) lift_cvts64(d)
#define CVTS32(d) lift_cvts32(d)
#define CVTU(d) lift_cvtu(d)
static inline uint64_t lift_sdiv64(uint64_t a, uint64_t b) { int64_t x = (int64_t)a, y = (int64_t)b; if (y == 0) return 0; if (x == INT64_MIN && y == -1) return (uint64_t)x; return (uint64_t)(x / y); }
static inline uint32_t lift_sdiv32(uint64_t a, uint64_t b) { int32_t x = (int32_t)a, y = (int32_t)b; if (y == 0) return 0; if (x == INT32_MIN && y == -1) return (uint32_t)x; return (uint32_t)(x / y); }
#define SDIV64(a, b) lift_sdiv64((a), (b))
#define SDIV32(a, b) lift_sdiv32((a), (b))
#endif
