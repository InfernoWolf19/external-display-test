// Y34SplashTypes.h : the pure part of -[SBApplication(Classic_Internal) _calculateSupportedTypesForSplashBoard] of iPadOS 16.2 (20C65, 0x1c733c13c, 126 instructions).  Plain C so
// tools/a2c/tests/splash_test.py can compile exactly this function and compare it with the lifted 16.2 machine code on all 8192 combinations of the 13 boolean queries.
// Inputs are the answers of the queries in the order the 16.2 body asks them; `types` is the current _supportedTypes ivar (+0xc0), the result is its new value.
// 16.2 vs 16.0 (0x1c5ec8d2c): the ONLY difference is in the last step (type 1 block): 16.0 used `sydney && ![_appInfo isBeta]` where 16.2 uses `sydney` (isBeta is not asked any more).
#ifndef Y34_SPLASHTYPES_H
#define Y34_SPLASHTYPES_H
#include <stdint.h>

typedef struct {
    uint8_t monarch, tigris, peace, yukon, azul, new2020Phones, newRoundPads, sky, sydney;   // -[_appInfo isMonarchLinked / ...], -[self _isNewEnoughToKnow...]
    uint8_t supportsType2, wantsFullScreen, supportsType1;                                  // -[self _supportsApplicationType:2], -[_appInfo wantsFullScreen], -[self _supportsApplicationType:1]
} Y34SplashQuery;

static inline uint64_t Y34_SplashTypes(uint64_t types, Y34SplashQuery q) {
    if (q.supportsType2) {
        // wantsFullScreen picks the SDK generation flag that gates each bit; without it every bit is gated by Monarch (0x1c733c1f4..0x1c733c21c: csel w, flagX, monarch, ne)
        uint8_t g_tigris = q.wantsFullScreen ? q.tigris : q.monarch;
        uint8_t g_round  = q.wantsFullScreen ? q.newRoundPads : q.monarch;
        uint8_t g_azul   = q.wantsFullScreen ? q.azul : q.monarch;
        uint8_t g_yukon  = q.wantsFullScreen ? q.yukon : q.monarch;
        uint8_t g_sky    = q.wantsFullScreen ? q.sky : q.monarch;
        uint8_t g_sydney = q.wantsFullScreen ? q.sydney : q.monarch;
        uint64_t t = types | (q.monarch ? 0x1000002ull : 0x2ull);
        if (g_tigris) t |= 0x200000ull;                     // csel x9, x14, x16(= x14 | 0x200000), eq  ->  w9 == 0 keeps x14
        if (g_round)  t |= 0x2420000ull;
        if (g_azul)   t |= 0x80000ull;
        if (g_yukon)  t |= 0x40000ull;
        if (g_sky)    t |= 0x10000ull;
        types = t;                                          // str x9, [x19, _supportedTypes]
        if (g_sydney) types |= 0x4900000ull;                // orr x9, x9, #0x4900000 ; str
    }
    if (q.supportsType1) {
        uint64_t t = types | (q.tigris ? 0x5dull : 0x1dull);
        if (q.peace) t |= 0x200ull;
        types = t;                                          // str
        uint8_t early = (uint8_t)(q.new2020Phones | q.azul);
        uint64_t extra = early ? (q.new2020Phones ? 0x4a0ull : 0x20ull) : 0ull;
        if ((uint8_t)(early | q.sydney) == 1) {             // cmp w11, #1 ; b.ne (skip): any of 2020 phones / azul / sydney
            t |= extra;
            if (q.sydney) t |= 0x900ull;                    // 16.0: if (sydney && !isBeta)
            types = t;                                      // str
        }
    }
    return types;
}
#endif
