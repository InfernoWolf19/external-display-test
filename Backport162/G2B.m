// group2b-reconstruct.hooks.m
//
// DRAFT (Logos). Reconstruction of the pieces that group2-layout-data.hooks.m left as NOT PORTABLE / TODO.
// Self-contained helpers are prefixed BP2B_ (they do not depend on the static helpers of group2-layout-data.hooks.m;
// they only look up the group-2 classes (BP162ChamoisOverlappingController, BP162VCState ...) through the runtime).
// Item numbers in the comments are the ITEM numbers of group2b-reconstruct.md.
//
// Rules followed: ivars by name (ivar_getOffset), every private call guarded (respondsToSelector:/class lookup),
// no crash on nil, %orig on its own line, messages to `id` named `type` through objc_msgSend casts.
// Compile with ARC. Each %group is initialised by BP2B_Setup() in the order given in the md SUMMARY.

#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wunused-variable"
#pragma clang diagnostic ignored "-Wundeclared-selector"
#pragma clang diagnostic ignored "-Wunused-parameter"

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <string.h>
#import <dlfcn.h>
#import <math.h>

#import <rootless.h>
#import "BP.h"

// ----------------------------------------------------------------------------------------------- tiny helpers
static inline id BP2B_Obj(id o, SEL s) { return (o && [o respondsToSelector:s]) ? ((id (*)(id, SEL))objc_msgSend)(o, s) : nil; }
static inline id BP2B_Obj1(id o, SEL s, id a) { return (o && [o respondsToSelector:s]) ? ((id (*)(id, SEL, id))objc_msgSend)(o, s, a) : nil; }
static inline BOOL BP2B_Bool(id o, SEL s) { return (o && [o respondsToSelector:s]) ? ((BOOL (*)(id, SEL))objc_msgSend)(o, s) : NO; }
static inline BOOL BP2B_Bool1(id o, SEL s, id a) { return (o && [o respondsToSelector:s]) ? ((BOOL (*)(id, SEL, id))objc_msgSend)(o, s, a) : NO; }
static inline double BP2B_Dbl(id o, SEL s) { return (o && [o respondsToSelector:s]) ? ((double (*)(id, SEL))objc_msgSend)(o, s) : 0.0; }
static inline long long BP2B_LL(id o, SEL s) { return (o && [o respondsToSelector:s]) ? ((long long (*)(id, SEL))objc_msgSend)(o, s) : 0; }
static inline CGRect BP2B_Rect(id o, SEL s) { return (o && [o respondsToSelector:s]) ? ((CGRect (*)(id, SEL))objc_msgSend)(o, s) : CGRectZero; }
static inline CGSize BP2B_Size(id o, SEL s) { return (o && [o respondsToSelector:s]) ? ((CGSize (*)(id, SEL))objc_msgSend)(o, s) : CGSizeZero; }
static inline CGPoint BP2B_Point(id o, SEL s) { return (o && [o respondsToSelector:s]) ? ((CGPoint (*)(id, SEL))objc_msgSend)(o, s) : CGPointZero; }

static id BP2B_IvarObj(id obj, const char *name) {
    if (!obj) return nil;
    Ivar iv = class_getInstanceVariable(object_getClass(obj), name);
    if (!iv) return nil;
    const char *enc = ivar_getTypeEncoding(iv);
    if (!enc || (enc[0] != '@' && enc[0] != '#')) return nil;
    return object_getIvar(obj, iv);
}
static BOOL BP2B_IvarGet(id obj, const char *name, void *buf, size_t size) {
    if (!obj || !buf) return NO;
    Ivar iv = class_getInstanceVariable(object_getClass(obj), name);
    if (!iv) return NO;
    const char *enc = ivar_getTypeEncoding(iv);
    NSUInteger sz = 0;
    if (!enc) return NO;
    @try { NSGetSizeAndAlignment(enc, &sz, NULL); } @catch (...) { return NO; }
    if (sz != size) return NO;
    memcpy(buf, (const char *)(__bridge void *)obj + ivar_getOffset(iv), size);
    return YES;
}
static BOOL BP2B_IvarSet(id obj, const char *name, const void *buf, size_t size) {
    if (!obj || !buf) return NO;
    Ivar iv = class_getInstanceVariable(object_getClass(obj), name);
    if (!iv) return NO;
    const char *enc = ivar_getTypeEncoding(iv);
    NSUInteger sz = 0;
    if (!enc) return NO;
    @try { NSGetSizeAndAlignment(enc, &sz, NULL); } @catch (...) { return NO; }
    if (sz != size) return NO;
    memcpy((char *)(__bridge void *)obj + ivar_getOffset(iv), buf, size);
    return YES;
}
static BOOL BP2B_AddIfMissing(Class c, const char *sel, IMP imp, const char *types) {
    if (!c || !imp) return NO;
    SEL s = sel_registerName(sel);
    if (class_getInstanceMethod(c, s)) return NO;
    return class_addMethod(c, s, imp, types);
}
// Replace a method with a full reimplementation; returns the original IMP (NULL if the method does not exist).
static IMP BP2B_Replace(Class c, const char *sel, IMP imp) {
    if (!c || !imp) return NULL;
    Method m = class_getInstanceMethod(c, sel_registerName(sel));
    if (!m) return NULL;
    IMP old = method_getImplementation(m);
    // class_replaceMethod (not method_setImplementation): never patches a superclass' method when `sel` is only inherited.
    class_replaceMethod(c, sel_registerName(sel), imp, method_getTypeEncoding(m));
    return old;
}

// Feature gate: <jbroot>/tmp/Backport162.off or Backport162.off.<name> disables (checked at most once a second per name).
#include <unistd.h>
#include <time.h>
static BOOL BP2B_Enabled(const char *name) { return BP_OnName(name); }     // INTEGRATION: shared switch infrastructure (BP.h)

// =================================================================================================================
// ITEM 4: CoreGraphics CGRegion SPI with a complete fallback.   DONE
//
// BP2B_Rgn is the function table the controller port should call instead of its own gRgn (same signatures as the
// CoreGraphics SPI, results are +1 CFTypeRef objects, NULL on failure).  When every CoreGraphics symbol resolves the
// real ones are used.  Otherwise (or when Backport162.off.cgregion exists) the BP2BRegion fallback is used.
// =================================================================================================================

@interface BP2BRegion : NSObject {
@public
    // canonical form: disjoint rects, sorted by (y, x), vertically merged where identical x-runs repeat
    NSMutableArray<NSValue *> *_rects;
}
+ (instancetype)regionWithRect:(CGRect)r;
- (CGRect)boundingBox;
- (BOOL)isEmpty;
@end

static BOOL BP2B_RectsEmpty(CGRect r) { return !(r.size.width > 0 && r.size.height > 0) || isnan(r.origin.x) || isnan(r.origin.y); }

// Builds the canonical rect list for an arbitrary combination: cell(i,j) is in the result when op(inA, inB) is true.
typedef enum { BP2BOpUnion, BP2BOpDifference, BP2BOpIntersection } BP2BOp;

static BOOL BP2B_CellIn(NSArray<NSValue *> *rs, double cx, double cy) {
    for (NSValue *v in rs) {
        CGRect r = v.CGRectValue;
        if (cx >= r.origin.x && cx < r.origin.x + r.size.width && cy >= r.origin.y && cy < r.origin.y + r.size.height) return YES;
    }
    return NO;
}

static NSMutableArray<NSValue *> *BP2B_Combine(NSArray<NSValue *> *a, NSArray<NSValue *> *b, BP2BOp op) {
    NSMutableArray<NSNumber *> *xs = [NSMutableArray array], *ys = [NSMutableArray array];
    for (NSArray<NSValue *> *rs in @[a, b]) {
        for (NSValue *v in rs) {
            CGRect r = v.CGRectValue;
            [xs addObject:@(r.origin.x)]; [xs addObject:@(r.origin.x + r.size.width)];
            [ys addObject:@(r.origin.y)]; [ys addObject:@(r.origin.y + r.size.height)];
        }
    }
    NSArray *sx = [[NSSet setWithArray:xs].allObjects sortedArrayUsingSelector:@selector(compare:)];
    NSArray *sy = [[NSSet setWithArray:ys].allObjects sortedArrayUsingSelector:@selector(compare:)];
    // rows of x-runs
    NSMutableArray<NSMutableArray<NSValue *> *> *rows = [NSMutableArray array];   // each row: runs as CGRect (with the band's y/height)
    for (NSUInteger j = 0; j + 1 < sy.count; j++) {
        double y0 = [sy[j] doubleValue], y1 = [sy[j + 1] doubleValue];
        double cy = (y0 + y1) * 0.5;
        NSMutableArray<NSValue *> *runs = [NSMutableArray array];
        double runStart = 0; BOOL inRun = NO;
        for (NSUInteger i = 0; i + 1 < sx.count; i++) {
            double x0 = [sx[i] doubleValue], x1 = [sx[i + 1] doubleValue];
            double cx = (x0 + x1) * 0.5;
            BOOL ia = BP2B_CellIn(a, cx, cy), ib = BP2B_CellIn(b, cx, cy), in;
            switch (op) {
                case BP2BOpUnion: in = ia || ib; break;
                case BP2BOpDifference: in = ia && !ib; break;
                default: in = ia && ib; break;
            }
            if (in && !inRun) { runStart = x0; inRun = YES; }
            if (!in && inRun) { [runs addObject:[NSValue valueWithCGRect:CGRectMake(runStart, y0, x0 - runStart, y1 - y0)]]; inRun = NO; }
            if (in && i + 2 == sx.count) { [runs addObject:[NSValue valueWithCGRect:CGRectMake(runStart, y0, x1 - runStart, y1 - y0)]]; inRun = NO; }
        }
        [rows addObject:runs];
    }
    // merge vertically adjacent bands with identical runs
    NSMutableArray<NSValue *> *out = [NSMutableArray array];
    NSMutableArray<NSValue *> *open = nil;       // runs currently being extended
    for (NSUInteger j = 0; j < rows.count; j++) {
        NSMutableArray<NSValue *> *runs = rows[j];
        BOOL same = open && open.count == runs.count;
        if (same) {
            for (NSUInteger k = 0; k < runs.count && same; k++) {
                CGRect p = open[k].CGRectValue, q = runs[k].CGRectValue;
                same = p.origin.x == q.origin.x && p.size.width == q.size.width && p.origin.y + p.size.height == q.origin.y;
            }
        }
        if (same) {
            for (NSUInteger k = 0; k < runs.count; k++) {
                CGRect p = open[k].CGRectValue, q = runs[k].CGRectValue;
                p.size.height += q.size.height;
                open[k] = [NSValue valueWithCGRect:p];
            }
        } else {
            if (open) [out addObjectsFromArray:open];
            open = runs.count ? [runs mutableCopy] : nil;
        }
    }
    if (open) [out addObjectsFromArray:open];
    return out;
}

@implementation BP2BRegion
+ (instancetype)regionWithRect:(CGRect)r {
    BP2BRegion *g = [BP2BRegion new];
    g->_rects = [NSMutableArray array];
    CGRect s = CGRectStandardize(r);
    if (!BP2B_RectsEmpty(s) && isfinite(s.origin.x) && isfinite(s.origin.y) && isfinite(s.size.width) && isfinite(s.size.height))
        [g->_rects addObject:[NSValue valueWithCGRect:s]];
    return g;
}
- (CGRect)boundingBox {
    if (!_rects.count) return CGRectZero;
    CGRect u = _rects.firstObject.CGRectValue;
    for (NSValue *v in _rects) u = CGRectUnion(u, v.CGRectValue);
    return u;
}
- (BOOL)isEmpty { return _rects.count == 0; }
@end

typedef const void *BP2BRgnRef;
static BP2BRgnRef BP2B_FbWithRect(CGRect r) { return CFBridgingRetain([BP2BRegion regionWithRect:r]); }
static BP2BRgnRef BP2B_FbOp(BP2BRgnRef a, BP2BRgnRef b, BP2BOp op) {
    BP2BRegion *x = (__bridge BP2BRegion *)a, *y = (__bridge BP2BRegion *)b;
    if (![x isKindOfClass:[BP2BRegion class]] || ![y isKindOfClass:[BP2BRegion class]]) return NULL;
    BP2BRegion *g = [BP2BRegion new];
    g->_rects = BP2B_Combine(x->_rects, y->_rects, op);
    return CFBridgingRetain(g);
}
static BP2BRgnRef BP2B_FbUnion(BP2BRgnRef a, BP2BRgnRef b) { return BP2B_FbOp(a, b, BP2BOpUnion); }
static BP2BRgnRef BP2B_FbDiff(BP2BRgnRef a, BP2BRgnRef b) { return BP2B_FbOp(a, b, BP2BOpDifference); }
static BP2BRgnRef BP2B_FbInter(BP2BRgnRef a, BP2BRgnRef b) { return BP2B_FbOp(a, b, BP2BOpIntersection); }
static bool BP2B_FbIsEmpty(BP2BRgnRef a) { BP2BRegion *x = (__bridge BP2BRegion *)a; return ![x isKindOfClass:[BP2BRegion class]] || [x isEmpty]; }
static CGRect BP2B_FbBBox(BP2BRgnRef a) { BP2BRegion *x = (__bridge BP2BRegion *)a; return [x isKindOfClass:[BP2BRegion class]] ? [x boundingBox] : CGRectZero; }
static bool BP2B_FbEqual(BP2BRgnRef a, BP2BRgnRef b) {
    BP2BRegion *x = (__bridge BP2BRegion *)a, *y = (__bridge BP2BRegion *)b;
    if (![x isKindOfClass:[BP2BRegion class]] || ![y isKindOfClass:[BP2BRegion class]]) return false;
    return [x->_rects isEqualToArray:y->_rects];
}
static bool BP2B_FbIntersects(BP2BRgnRef a, BP2BRgnRef b) {
    BP2BRgnRef i = BP2B_FbInter(a, b);
    if (!i) return false;
    bool r = !BP2B_FbIsEmpty(i);
    CFRelease(i);
    return r;
}

static struct {
    BP2BRgnRef (*withRect)(CGRect);
    BP2BRgnRef (*unionR)(BP2BRgnRef, BP2BRgnRef);
    BP2BRgnRef (*diffR)(BP2BRgnRef, BP2BRgnRef);
    BP2BRgnRef (*interR)(BP2BRgnRef, BP2BRgnRef);
    bool (*isEmpty)(BP2BRgnRef);
    CGRect (*bbox)(BP2BRgnRef);
    bool (*equalR)(BP2BRgnRef, BP2BRgnRef);
    bool (*intersects)(BP2BRgnRef, BP2BRgnRef);
    BOOL usingFallback;
} BP2B_Rgn;

static void BP2B_ResolveRegionTable(BOOL forceFallback) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *a = dlsym(RTLD_DEFAULT, "CGRegionCreateWithRect"), *b = dlsym(RTLD_DEFAULT, "CGRegionCreateUnionWithRegion");
        void *c = dlsym(RTLD_DEFAULT, "CGRegionCreateDifferenceWithRegion"), *d = dlsym(RTLD_DEFAULT, "CGRegionCreateIntersectionWithRegion");
        void *e = dlsym(RTLD_DEFAULT, "CGRegionIsEmpty"), *f = dlsym(RTLD_DEFAULT, "CGRegionGetBoundingBox");
        void *g = dlsym(RTLD_DEFAULT, "CGRegionEqualToRegion"), *h = dlsym(RTLD_DEFAULT, "CGRegionIntersectsRegion");
        if (!forceFallback && a && b && c && d && e && f && g && h) {
            BP2B_Rgn.withRect = (BP2BRgnRef (*)(CGRect))a;
            BP2B_Rgn.unionR = (BP2BRgnRef (*)(BP2BRgnRef, BP2BRgnRef))b;
            BP2B_Rgn.diffR = (BP2BRgnRef (*)(BP2BRgnRef, BP2BRgnRef))c;
            BP2B_Rgn.interR = (BP2BRgnRef (*)(BP2BRgnRef, BP2BRgnRef))d;
            BP2B_Rgn.isEmpty = (bool (*)(BP2BRgnRef))e;
            BP2B_Rgn.bbox = (CGRect (*)(BP2BRgnRef))f;
            BP2B_Rgn.equalR = (bool (*)(BP2BRgnRef, BP2BRgnRef))g;
            BP2B_Rgn.intersects = (bool (*)(BP2BRgnRef, BP2BRgnRef))h;
            BP2B_Rgn.usingFallback = NO;
        } else {
            BP2B_Rgn.withRect = BP2B_FbWithRect; BP2B_Rgn.unionR = BP2B_FbUnion; BP2B_Rgn.diffR = BP2B_FbDiff;
            BP2B_Rgn.interR = BP2B_FbInter; BP2B_Rgn.isEmpty = BP2B_FbIsEmpty; BP2B_Rgn.bbox = BP2B_FbBBox;
            BP2B_Rgn.equalR = BP2B_FbEqual; BP2B_Rgn.intersects = BP2B_FbIntersects; BP2B_Rgn.usingFallback = YES;
        }
    });
}

// Compares the fallback against CoreGraphics on random rect sets; logs the number of mismatches (debug aid, run from a debug flag).
static void BP2B_RegionSelfTest(void) {
    void *a = dlsym(RTLD_DEFAULT, "CGRegionCreateWithRect");
    if (!a || BP2B_Rgn.usingFallback) { BP_Log(@"[g2b] region selftest: CoreGraphics SPI unavailable, fallback in use"); return; }
    int bad = 0;
    for (int n = 0; n < 200; n++) {
        CGRect r1 = CGRectMake(arc4random_uniform(50), arc4random_uniform(50), 1 + arc4random_uniform(60), 1 + arc4random_uniform(60));
        CGRect r2 = CGRectMake(arc4random_uniform(50), arc4random_uniform(50), 1 + arc4random_uniform(60), 1 + arc4random_uniform(60));
        CGRect r3 = CGRectMake(arc4random_uniform(50), arc4random_uniform(50), 1 + arc4random_uniform(60), 1 + arc4random_uniform(60));
        BP2BRgnRef c1 = BP2B_Rgn.withRect(r1), c2 = BP2B_Rgn.withRect(r2), c3 = BP2B_Rgn.withRect(r3);
        BP2BRgnRef f1 = BP2B_FbWithRect(r1), f2 = BP2B_FbWithRect(r2), f3 = BP2B_FbWithRect(r3);
        BP2BRgnRef cu = BP2B_Rgn.unionR(c1, c2), cd = BP2B_Rgn.diffR(cu, c3), ci = BP2B_Rgn.interR(cu, c3);
        BP2BRgnRef fu = BP2B_FbUnion(f1, f2), fd = BP2B_FbDiff(fu, f3), fi = BP2B_FbInter(fu, f3);
        if (BP2B_Rgn.isEmpty(cd) != BP2B_FbIsEmpty(fd)) bad++;
        if (BP2B_Rgn.isEmpty(ci) != BP2B_FbIsEmpty(fi)) bad++;
        if (!BP2B_Rgn.isEmpty(cd) && !CGRectEqualToRect(BP2B_Rgn.bbox(cd), BP2B_FbBBox(fd))) bad++;
        if (BP2B_Rgn.intersects(cu, c3) != BP2B_FbIntersects(fu, f3)) bad++;
        BP2BRgnRef all[] = { c1, c2, c3, cu, cd, ci, f1, f2, f3, fu, fd, fi };
        for (size_t k = 0; k < sizeof all / sizeof all[0]; k++) if (all[k]) CFRelease(all[k]);
    }
    BP_Log(@"[g2b] region selftest mismatches=%d", bad);
}

// =================================================================================================================
// ITEM 1: SBDisplayItemLayoutAttributes data model (16.2: attributedSize / normalizedCenter / semantic size types)
//
// DESIGN (see md ITEM 1): the 16.0 object already stores NORMALISED values in _size / _center /
// _userConfiguredSizeBeforeOverlapping (fractions of the container when both components <= 1, absolute points otherwise)
// and _fullyOccludedPeekingCenter == 16.2 _unoccludedPeekingCenter.  16.2 only adds, per size, a referenceBounds rect and a
// semanticSizeType (0..9).  Those two per size are kept in an immutable associated object (BP2BAttrExtras), the 16.0 ivars
// are reused for everything else (read/written by ivar NAME).  Every method that creates a new attributes object is replaced
// by a full reimplementation that goes through the 16.0 designated init (so _hash stays right) and then re-attaches the
// extras.  No runtime subclass, no +alloc swizzle: objects are also created by SpringBoard code we do not control
// (plist/protobuf/copy), an associated object survives all of them as long as the creating methods are ours.
// =================================================================================================================

typedef struct { CGSize normalizedSize; CGRect referenceBounds; long long semanticSizeType; } BP2BAttrSize;   // == SBDisplayItemAttributedSize
#define BP2B_ATTRSIZE_ENC "{SBDisplayItemAttributedSize={CGSize=dd}{CGRect={CGPoint=dd}{CGSize=dd}}q}"

static BP2BAttrSize BP2B_AttrSizeUnspecified(void) {                           // 162 0x1c75cedc4
    BP2BAttrSize s; s.normalizedSize = CGSizeZero; s.referenceBounds = CGRectNull; s.semanticSizeType = 0; return s;
}
static BOOL BP2B_AttrSizeIsUnspecified(BP2BAttrSize s) { return s.normalizedSize.width == 0 && s.normalizedSize.height == 0; }   // 162 0x1c75cf03c

static int (*gBP2B_Eq)(double, double), (*gBP2B_LE)(double, double), (*gBP2B_GT)(double, double), (*gBP2B_LT)(double, double);
static void BP2B_ResolveBS(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gBP2B_Eq = dlsym(RTLD_DEFAULT, "BSFloatEqualToFloat");
        gBP2B_LE = dlsym(RTLD_DEFAULT, "BSFloatLessThanOrEqualToFloat");
        gBP2B_GT = dlsym(RTLD_DEFAULT, "BSFloatGreaterThanFloat");
        gBP2B_LT = dlsym(RTLD_DEFAULT, "BSFloatLessThanFloat");
    });
}
static inline BOOL BP2B_FEq(double a, double b) { BP2B_ResolveBS(); return gBP2B_Eq ? gBP2B_Eq(a, b) != 0 : fabs(a - b) < 1e-9; }
static inline BOOL BP2B_FLE(double a, double b) { BP2B_ResolveBS(); return gBP2B_LE ? gBP2B_LE(a, b) != 0 : (a < b || BP2B_FEq(a, b)); }
static inline BOOL BP2B_FGT(double a, double b) { BP2B_ResolveBS(); return gBP2B_GT ? gBP2B_GT(a, b) != 0 : (a > b && !BP2B_FEq(a, b)); }
static inline BOOL BP2B_FLT(double a, double b) { BP2B_ResolveBS(); return gBP2B_LT ? gBP2B_LT(a, b) != 0 : (a < b && !BP2B_FEq(a, b)); }

// _SBDisplayItemAttributedSizeInfer(size, bounds, defaultSize, screenEdgePadding)   162 0x1c75cedfc (decoded line by line)
// semanticSizeType: 0 none, 1 full width, 2 full height, 3 full both, 4 default width, 5 default height, 6 default size,
//                   7 padded width (bounds.w - 2p), 8 padded height, 9 padded both.
static BP2BAttrSize BP2B_AttrSizeInfer(CGSize size, CGRect bounds, CGSize defSize, double pad) {
    BOOL fw = BP2B_FEq(size.width, bounds.size.width), fh = BP2B_FEq(size.height, bounds.size.height);
    long long t = fw ? ((fw && fh) ? 3 : 1) : 2;               // csinc/csel chain: both -> 3, width only -> 1, otherwise 2 (tested next)
    if (!fw && !fh) {
        BOOL dw = BP2B_FEq(size.width, defSize.width), dh = BP2B_FEq(size.height, defSize.height);
        t = dw ? ((dw && dh) ? 6 : 4) : 5;
        if (!dw && !dh) {
            double p2 = pad + pad;
            BOOL pw = BP2B_FEq(size.width, bounds.size.width - p2), ph = BP2B_FEq(size.height, bounds.size.height - p2);
            t = pw ? ((pw && ph) ? 9 : 7) : (ph ? 8 : 0);
        }
    }
    BP2BAttrSize r;
    r.normalizedSize = CGSizeMake(size.width / bounds.size.width, size.height / bounds.size.height);
    r.referenceBounds = bounds;
    r.semanticSizeType = t;
    return r;
}
// Subtle point kept from the disassembly: for the first test (full bounds) "height only" yields 2, "width only" yields 1.
// The second test (default size) yields 6 / 4 (width matches) / 5 (otherwise, also reached when only the height matches).

// Context set by the wrapper around the 16.0 -_frameForLayoutRole:... (item 3): the 16.0 one-argument `sizeInBounds:` has no
// default size / padding argument, 16.2 passes chamoisLayoutAttributes.defaultWindowSize / screenEdgePadding. While a calculator
// frame computation runs, the legacy entry points use these values, which makes the unchanged 16.0 frame code size windows
// with the exact 16.2 semantics (types 4/5/6 follow the default size, 7/8/9 the padding, shrink clamp).
static __thread struct { BOOL on; CGSize def; double pad; } gBP2B_Ctx;

// -[SBDisplayItemLayoutAttributes _sizeForAttributedSize:inBounds:defaultSize:screenEdgePadding:]   162 0x1c75d0a3c
// `legacy` = YES when called from the 16.0 one-argument entry points (no default size known): types 4/5/6 then fall back to the scaled value.
static CGSize BP2B_SizeForAttributedSize(BP2BAttrSize a, CGRect bounds, CGSize defSize, double pad, BOOL legacy) {
    double curW = bounds.size.width, curH = bounds.size.height;
    if (!(BP2B_FLE(a.normalizedSize.width, 10.0) && BP2B_FLE(a.normalizedSize.height, 10.0))) return a.normalizedSize;   // legacy absolute size
    double refW = curW, refH = curH;
    if (!CGRectIsEmpty(a.referenceBounds)) { refW = a.referenceBounds.size.width; refH = a.referenceBounds.size.height; }
    double scaledW = refW * a.normalizedSize.width, scaledH = refH * a.normalizedSize.height;
    double W = scaledW, H = scaledH;
    BOOL rotated = BP2B_FEq(curW, refH) && BP2B_FEq(curH, refW);
    if (rotated) {
        long long t = a.semanticSizeType;
        if (legacy && (t == 4 || t == 5 || t == 6)) t = 0;
        switch (t) {
            case 1: W = curW; break;
            case 2: H = curH; break;
            case 3: W = curW; H = curH; break;
            case 4: W = defSize.width; break;
            case 5: H = defSize.height; break;
            case 6: W = defSize.width; H = defSize.height; break;
            case 7: W = curW - (pad + pad); break;
            case 8: H = curH - (pad + pad); break;
            case 9: W = curW - (pad + pad); H = curH - (pad + pad); break;
            default: break;
        }
    } else if (BP2B_FLT(curW * curH, refH * refW) && BP2B_FGT(defSize.width, 0) && BP2B_FGT(defSize.height, 0)) {
        // the container got smaller than the reference: never larger than the default size
        W = fmin(defSize.width, fmax(scaledW, 0));
        H = fmin(defSize.height, fmax(scaledH, 0));
        return CGSizeMake(W, H);                                     // this path returns without the final clamp (0x1c75d0b74 -> exit)
    }
    return CGSizeMake(fmin(curW, fmax(W, 0)), fmin(curH, fmax(H, 0)));
}

// -centerInBounds: 16.2 0x1c75cf654 (threshold 10.0 instead of 16.0's 1.0, bounds.size only)
static CGPoint BP2B_CenterInBounds(CGPoint c, CGRect bounds) {
    if (BP2B_FLE(c.x, 10.0) && BP2B_FLE(c.y, 10.0)) return CGPointMake(bounds.size.width * c.x, bounds.size.height * c.y);
    return c;
}

@interface BP2BAttrExtras : NSObject {
@public
    CGRect sizeRef; long long sizeType;
    CGRect userRef; long long userType;
}
@end
@implementation BP2BAttrExtras
- (instancetype)init { if ((self = [super init])) { sizeRef = CGRectNull; userRef = CGRectNull; } return self; }
@end

static const void *kBP2B_AttrExtras = &kBP2B_AttrExtras;
static BP2BAttrExtras *BP2B_Extras(id attrs) { return attrs ? objc_getAssociatedObject(attrs, kBP2B_AttrExtras) : nil; }
static void BP2B_SetExtras(id attrs, BP2BAttrExtras *e) { if (attrs) objc_setAssociatedObject(attrs, kBP2B_AttrExtras, e, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
static BOOL BP2B_ExtrasDefault(BP2BAttrExtras *e) {
    return !e || ((CGRectIsNull(e->sizeRef) || CGRectIsEmpty(e->sizeRef)) && e->sizeType == 0 && (CGRectIsNull(e->userRef) || CGRectIsEmpty(e->userRef)) && e->userType == 0);
}
static BOOL BP2B_ExtrasEqual(BP2BAttrExtras *a, BP2BAttrExtras *b) {
    if (BP2B_ExtrasDefault(a) && BP2B_ExtrasDefault(b)) return YES;
    if (!a || !b) return NO;
    return CGRectEqualToRect(a->sizeRef, b->sizeRef) && a->sizeType == b->sizeType && CGRectEqualToRect(a->userRef, b->userRef) && a->userType == b->userType;
}

// ---- raw field access (ivars by NAME; types verified through NSGetSizeAndAlignment) ---------------------------------
typedef struct {
    long long orient, time, policy, occlusion;
    CGSize size, user; CGPoint center, peek;
} BP2BAttrFields;

static BOOL BP2B_ReadFields(id a, BP2BAttrFields *f) {
    if (!a || !f) return NO;
    BOOL ok = BP2B_IvarGet(a, "_contentOrientation", &f->orient, sizeof f->orient)
           && BP2B_IvarGet(a, "_lastInteractionTime", &f->time, sizeof f->time)
           && BP2B_IvarGet(a, "_sizingPolicy", &f->policy, sizeof f->policy)
           && BP2B_IvarGet(a, "_occlusionState", &f->occlusion, sizeof f->occlusion)
           && BP2B_IvarGet(a, "_size", &f->size, sizeof f->size)
           && BP2B_IvarGet(a, "_userConfiguredSizeBeforeOverlapping", &f->user, sizeof f->user)
           && BP2B_IvarGet(a, "_center", &f->center, sizeof f->center)
           && BP2B_IvarGet(a, "_fullyOccludedPeekingCenter", &f->peek, sizeof f->peek);
    return ok;
}

// The ORIGINAL 16.0 designated initialiser (kept before we replace anything).
typedef id (*BP2B_Init16)(id, SEL, long long, long long, long long, CGSize, CGPoint, long long, CGSize, CGPoint);
static BP2B_Init16 gBP2B_Init16;
static Class gBP2B_AttrClass;

static id BP2B_Make(BP2BAttrFields f, BP2BAttrExtras *e) {
    if (!gBP2B_AttrClass || !gBP2B_Init16) return nil;
    id o = ((id (*)(Class, SEL))objc_msgSend)(gBP2B_AttrClass, @selector(alloc));
    o = gBP2B_Init16(o, sel_registerName("initWithContentOrientation:lastInteractionTime:sizingPolicy:size:center:occlusionState:userConfiguredSizeBeforeOverlapping:fullyOccludedPeekingCenter:"),
                     f.orient, f.time, f.policy, f.size, f.center, f.occlusion, f.user, f.peek);
    if (o && !BP2B_ExtrasDefault(e)) BP2B_SetExtras(o, e);
    return o;
}
static BP2BAttrExtras *BP2B_CopyExtras(BP2BAttrExtras *e) {
    BP2BAttrExtras *n = [BP2BAttrExtras new];
    if (e) { n->sizeRef = e->sizeRef; n->sizeType = e->sizeType; n->userRef = e->userRef; n->userType = e->userType; }
    return n;
}

static BP2BAttrSize BP2B_GetAttributedSize(id a) {
    BP2BAttrFields f; BP2BAttrSize s = BP2B_AttrSizeUnspecified();
    if (!BP2B_ReadFields(a, &f)) return s;
    BP2BAttrExtras *e = BP2B_Extras(a);
    s.normalizedSize = f.size;
    if (e) { s.referenceBounds = e->sizeRef; s.semanticSizeType = e->sizeType; }
    return s;
}
static BP2BAttrSize BP2B_GetAttributedUserSize(id a) {
    BP2BAttrFields f; BP2BAttrSize s = BP2B_AttrSizeUnspecified();
    if (!BP2B_ReadFields(a, &f)) return s;
    BP2BAttrExtras *e = BP2B_Extras(a);
    s.normalizedSize = f.user;
    if (e) { s.referenceBounds = e->userRef; s.semanticSizeType = e->userType; }
    return s;
}

// ---- public conversion helpers used by items 2 and 3 ---------------------------------------------------------------------
// 16.2 attrs.sizeInBounds:defaultSize:screenEdgePadding: for any attributes object (16.0 persisted state included).
static CGSize BP2B_AttrsSizeInBounds(id attrs, CGRect bounds, CGSize defSize, double pad) {
    return BP2B_SizeForAttributedSize(BP2B_GetAttributedSize(attrs), bounds, defSize, pad, NO);
}
static CGSize BP2B_AttrsUserSizeInBounds(id attrs, CGRect bounds, CGSize defSize, double pad) {
    return BP2B_SizeForAttributedSize(BP2B_GetAttributedUserSize(attrs), bounds, defSize, pad, NO);
}
static CGPoint BP2B_AttrsCenterInBounds(id attrs, CGRect bounds) {
    BP2BAttrFields f;
    if (!BP2B_ReadFields(attrs, &f)) return CGPointZero;
    return BP2B_CenterInBounds(f.center, bounds);
}
// attributes by writing an ABSOLUTE size/center for the current container (what the 16.2 calculator does at the end of auto layout)
static id BP2B_AttrsBySettingAbsolute(id attrs, CGSize size, CGPoint center, BOOL setCenter, CGRect bounds, CGSize defSize, double pad) {
    BP2BAttrFields f;
    if (!BP2B_ReadFields(attrs, &f) || bounds.size.width <= 0 || bounds.size.height <= 0) return attrs;
    BP2BAttrSize s = BP2B_AttrSizeInfer(size, bounds, defSize, pad);
    BP2BAttrExtras *e = BP2B_CopyExtras(BP2B_Extras(attrs));
    f.size = s.normalizedSize; e->sizeRef = s.referenceBounds; e->sizeType = s.semanticSizeType;
    if (setCenter) f.center = CGPointMake(center.x / bounds.size.width, center.y / bounds.size.height);
    return BP2B_Make(f, e) ?: attrs;
}

// ---- the replacement / added methods ------------------------------------------------------------------------------------------
static IMP gOrigIsEqual, gOrigPlist, gOrigInitPlist;

static void BP2B_SetupAttributes(void) {
    Class c = objc_getClass("SBDisplayItemLayoutAttributes");
    if (!c) return;
    SEL initSel = sel_registerName("initWithContentOrientation:lastInteractionTime:sizingPolicy:size:center:occlusionState:userConfiguredSizeBeforeOverlapping:fullyOccludedPeekingCenter:");
    Method im = class_getInstanceMethod(c, initSel);
    if (!im || class_getInstanceMethod(c, sel_registerName("attributedSize"))) return;      // not 16.0, or already done
    // sanity: the ivars we depend on must exist with the expected sizes
    BP2BAttrFields probe;
    id sample = nil;
    {
        gBP2B_AttrClass = c;
        gBP2B_Init16 = (BP2B_Init16)method_getImplementation(im);
        sample = BP2B_Make((BP2BAttrFields){ 0, 0, 0, 0, CGSizeMake(0.5, 0.5), CGSizeZero, CGPointMake(0.5, 0.5), CGPointZero }, nil);
        if (!sample || !BP2B_ReadFields(sample, &probe) || probe.size.width != 0.5 || probe.center.y != 0.5) {
            BP_Log(@"[g2b] item1: SBDisplayItemLayoutAttributes ivar layout not as expected, data model emulation disabled");
            gBP2B_Init16 = NULL;
            return;
        }
    }
    const char *const SZ = BP2B_ATTRSIZE_ENC;
    (void)SZ;

    // --- 16.2 getters --------------------------------------------------------------------------------------------------------
    class_addMethod(c, sel_registerName("attributedSize"), imp_implementationWithBlock(^BP2BAttrSize(id me) { return BP2B_GetAttributedSize(me); }), "{SBDisplayItemAttributedSize={CGSize=dd}{CGRect={CGPoint=dd}{CGSize=dd}}q}16@0:8");
    class_addMethod(c, sel_registerName("attributedUserSizeBeforeOverlapping"), imp_implementationWithBlock(^BP2BAttrSize(id me) { return BP2B_GetAttributedUserSize(me); }), "{SBDisplayItemAttributedSize={CGSize=dd}{CGRect={CGPoint=dd}{CGSize=dd}}q}16@0:8");
    class_addMethod(c, sel_registerName("normalizedCenter"), imp_implementationWithBlock(^CGPoint(id me) { BP2BAttrFields f; return BP2B_ReadFields(me, &f) ? f.center : CGPointZero; }), "{CGPoint=dd}16@0:8");
    class_addMethod(c, sel_registerName("unoccludedPeekingCenter"), imp_implementationWithBlock(^CGPoint(id me) { BP2BAttrFields f; return BP2B_ReadFields(me, &f) ? f.peek : CGPointZero; }), "{CGPoint=dd}16@0:8");

    // --- 16.2 size queries (full algorithm) ----------------------------------------------------------------------------------
    class_addMethod(c, sel_registerName("sizeInBounds:defaultSize:screenEdgePadding:"), imp_implementationWithBlock(^CGSize(id me, CGRect b, CGSize d, double p) {
        return BP2B_AttrsSizeInBounds(me, b, d, p);
    }), "{CGSize=dd}64@0:8{CGRect={CGPoint=dd}{CGSize=dd}}16{CGSize=dd}48d56");
    class_addMethod(c, sel_registerName("userSizeBeforeOverlappingInBounds:defaultSize:screenEdgePadding:"), imp_implementationWithBlock(^CGSize(id me, CGRect b, CGSize d, double p) {
        return BP2B_AttrsUserSizeInBounds(me, b, d, p);
    }), "{CGSize=dd}64@0:8{CGRect={CGPoint=dd}{CGSize=dd}}16{CGSize=dd}48d56");
    class_addMethod(c, sel_registerName("_sizeForAttributedSize:inBounds:defaultSize:screenEdgePadding:"), imp_implementationWithBlock(^CGSize(id me, BP2BAttrSize a, CGRect b, CGSize d, double p) {
        return BP2B_SizeForAttributedSize(a, b, d, p, NO);
    }), "{CGSize=dd}80@0:8^v16{CGRect={CGPoint=dd}{CGSize=dd}}24{CGSize=dd}56d72");

    // --- 16.0 entry points that old (unported) callers still use: same algorithm without default size ------------------------------
    BP2B_Replace(c, "sizeInBounds:", imp_implementationWithBlock(^CGSize(id me, CGRect b) {
        return gBP2B_Ctx.on ? BP2B_SizeForAttributedSize(BP2B_GetAttributedSize(me), b, gBP2B_Ctx.def, gBP2B_Ctx.pad, NO)
                            : BP2B_SizeForAttributedSize(BP2B_GetAttributedSize(me), b, CGSizeZero, 0, YES);
    }));
    BP2B_Replace(c, "userConfiguredSizeBeforeOverlappingInBounds:", imp_implementationWithBlock(^CGSize(id me, CGRect b) {
        return gBP2B_Ctx.on ? BP2B_SizeForAttributedSize(BP2B_GetAttributedUserSize(me), b, gBP2B_Ctx.def, gBP2B_Ctx.pad, NO)
                            : BP2B_SizeForAttributedSize(BP2B_GetAttributedUserSize(me), b, CGSizeZero, 0, YES);
    }));
    BP2B_Replace(c, "centerInBounds:", imp_implementationWithBlock(^CGPoint(id me, CGRect b) { return BP2B_AttrsCenterInBounds(me, b); }));

    // --- constructors --------------------------------------------------------------------------------------------------------
    // 16.2 designated init: ...attributedSize:normalizedCenter:occlusionState:attributedUserSizeBeforeOverlapping:unoccludedPeekingCenter:
    IMP full = imp_implementationWithBlock(^id(id me, long long orient, long long time, long long policy, BP2BAttrSize sz, CGPoint center, long long occ, BP2BAttrSize user, CGPoint peek) {
        id o = gBP2B_Init16 ? gBP2B_Init16(me, initSel, orient, time, policy, sz.normalizedSize, center, occ, user.normalizedSize, peek) : nil;
        if (o) {
            BP2BAttrExtras *e = [BP2BAttrExtras new];
            e->sizeRef = sz.referenceBounds; e->sizeType = sz.semanticSizeType; e->userRef = user.referenceBounds; e->userType = user.semanticSizeType;
            if (!BP2B_ExtrasDefault(e)) BP2B_SetExtras(o, e);
        }
        return o;
    });
    class_addMethod(c, sel_registerName("initWithContentOrientation:lastInteractionTime:sizingPolicy:attributedSize:normalizedCenter:occlusionState:attributedUserSizeBeforeOverlapping:unoccludedPeekingCenter:"), full, "@184@0:8q16q24q32^v40{CGPoint=dd}48q64^v72{CGPoint=dd}80");
    // 16.2 convenience init (162 0x1c75cf15c): occlusion 0, user size Unspecified, peek (0,0)
    class_addMethod(c, sel_registerName("initWithContentOrientation:lastInteractionTime:sizingPolicy:attributedSize:normalizedCenter:"), imp_implementationWithBlock(^id(id me, long long orient, long long time, long long policy, BP2BAttrSize sz, CGPoint center) {
        id o = gBP2B_Init16 ? gBP2B_Init16(me, initSel, orient, time, policy, sz.normalizedSize, center, 0, CGSizeZero, CGPointZero) : nil;
        if (o) {
            BP2BAttrExtras *e = [BP2BAttrExtras new];
            e->sizeRef = sz.referenceBounds; e->sizeType = sz.semanticSizeType;
            if (!BP2B_ExtrasDefault(e)) BP2B_SetExtras(o, e);
        }
        return o;
    }), "@80@0:8q16q24q32^v40{CGPoint=dd}48");

    // --- attributesByModifying*: 16.2 names (added) and 16.0 names (replaced, they must carry the extras) -----------------------
#define BP2B_MOD_BEGIN(name, type, argname) \
    class_addMethod(c, sel_registerName(name), imp_implementationWithBlock(^id(id me, type argname) { \
        BP2BAttrFields f; if (!BP2B_ReadFields(me, &f)) return me; BP2BAttrExtras *e = BP2B_CopyExtras(BP2B_Extras(me));
#define BP2B_MOD_END(enc) \
        return BP2B_Make(f, e) ?: me; }), enc);
    BP2B_MOD_BEGIN("attributesByModifyingAttributedSize:", BP2BAttrSize, a)
        f.size = a.normalizedSize; e->sizeRef = a.referenceBounds; e->sizeType = a.semanticSizeType;
    BP2B_MOD_END("@24@0:8^v16")
    BP2B_MOD_BEGIN("attributesByModifyingAttributedUserSizeBeforeOverlapping:", BP2BAttrSize, a)
        f.user = a.normalizedSize; e->userRef = a.referenceBounds; e->userType = a.semanticSizeType;
    BP2B_MOD_END("@24@0:8^v16")
    BP2B_MOD_BEGIN("attributesByModifyingNormalizedCenter:", CGPoint, p)
        f.center = p;
    BP2B_MOD_END("@32@0:8{CGPoint=dd}16")
    BP2B_MOD_BEGIN("attributesByModifyingUnoccludedPeekingCenter:", CGPoint, p)
        f.peek = p;
    BP2B_MOD_END("@32@0:8{CGPoint=dd}16")
#undef BP2B_MOD_BEGIN
#undef BP2B_MOD_END

    // 16.0 modifiers (replaced; semantics of the 16.0 names kept, extras carried or reset where the value is replaced)
    BP2B_Replace(c, "attributesByModifyingSize:", imp_implementationWithBlock(^id(id me, CGSize s) {
        BP2BAttrFields f; if (!BP2B_ReadFields(me, &f)) return me;
        BP2BAttrExtras *e = BP2B_CopyExtras(BP2B_Extras(me)); f.size = s; e->sizeRef = CGRectNull; e->sizeType = 0;
        return BP2B_Make(f, e) ?: me; }));
    BP2B_Replace(c, "attributesByModifyingCenter:", imp_implementationWithBlock(^id(id me, CGPoint p) {
        BP2BAttrFields f; if (!BP2B_ReadFields(me, &f)) return me;
        f.center = p; return BP2B_Make(f, BP2B_Extras(me)) ?: me; }));
    BP2B_Replace(c, "attributesByModifyingSize:center:", imp_implementationWithBlock(^id(id me, CGSize s, CGPoint p) {
        BP2BAttrFields f; if (!BP2B_ReadFields(me, &f)) return me;
        BP2BAttrExtras *e = BP2B_CopyExtras(BP2B_Extras(me)); f.size = s; f.center = p; e->sizeRef = CGRectNull; e->sizeType = 0;
        return BP2B_Make(f, e) ?: me; }));
    BP2B_Replace(c, "attributesByModifyingUserConfiguredSizeBeforeOverlapping:", imp_implementationWithBlock(^id(id me, CGSize s) {
        BP2BAttrFields f; if (!BP2B_ReadFields(me, &f)) return me;
        BP2BAttrExtras *e = BP2B_CopyExtras(BP2B_Extras(me)); f.user = s; e->userRef = CGRectNull; e->userType = 0;
        return BP2B_Make(f, e) ?: me; }));
    BP2B_Replace(c, "attributesByModifyingFullyOccludedPeekingCenter:", imp_implementationWithBlock(^id(id me, CGPoint p) {
        BP2BAttrFields f; if (!BP2B_ReadFields(me, &f)) return me;
        f.peek = p; return BP2B_Make(f, BP2B_Extras(me)) ?: me; }));
    BP2B_Replace(c, "attributesByModifyingOcclusionState:", imp_implementationWithBlock(^id(id me, long long v) {
        BP2BAttrFields f; if (!BP2B_ReadFields(me, &f)) return me;
        f.occlusion = v; return BP2B_Make(f, BP2B_Extras(me)) ?: me; }));
    BP2B_Replace(c, "attributesByModifyingContentOrientation:", imp_implementationWithBlock(^id(id me, long long v) {
        BP2BAttrFields f; if (!BP2B_ReadFields(me, &f)) return me;
        f.orient = v; return BP2B_Make(f, BP2B_Extras(me)) ?: me; }));
    BP2B_Replace(c, "attributesByModifyingSizingPolicy:", imp_implementationWithBlock(^id(id me, long long v) {
        BP2BAttrFields f; if (!BP2B_ReadFields(me, &f)) return me;
        f.policy = v; return BP2B_Make(f, BP2B_Extras(me)) ?: me; }));
    BP2B_Replace(c, "attributesByModifyingLastInteractionTime:", imp_implementationWithBlock(^id(id me, long long v) {
        BP2BAttrFields f; if (!BP2B_ReadFields(me, &f)) return me;
        f.time = v; return BP2B_Make(f, BP2B_Extras(me)) ?: me; }));
    BP2B_Replace(c, "copyWithZone:", imp_implementationWithBlock(^id(id me, void *zone) {
        BP2BAttrFields f; if (!BP2B_ReadFields(me, &f)) return me;
        return BP2B_Make(f, BP2B_Extras(me)) ?: me; }));

    // --- equality (extras participate, like 16.2's field-by-field isEqual:) ------------------------------------------------------
    SEL isEq = @selector(isEqual:);
    gOrigIsEqual = BP2B_Replace(c, "isEqual:", imp_implementationWithBlock(^BOOL(id me, id other) {
        BOOL r = gOrigIsEqual ? ((BOOL (*)(id, SEL, id))gOrigIsEqual)(me, isEq, other) : (me == other);
        if (!r || me == other || !other) return r;
        return BP2B_ExtrasEqual(BP2B_Extras(me), BP2B_Extras(other));
    }));

    // --- persistence: plist carries the extras under the 16.2 key names; unknown keys are ignored by a 16.0 reader --------------
    SEL plistSel = sel_registerName("plistRepresentation");
    gOrigPlist = BP2B_Replace(c, "plistRepresentation", imp_implementationWithBlock(^id(id me) {
        id d = gOrigPlist ? ((id (*)(id, SEL))gOrigPlist)(me, plistSel) : nil;
        BP2BAttrExtras *e = BP2B_Extras(me);
        if (![d isKindOfClass:[NSDictionary class]] || BP2B_ExtrasDefault(e)) return d;
        NSMutableDictionary *m = [d mutableCopy];
        CFDictionaryRef r1 = CGRectCreateDictionaryRepresentation(e->sizeRef), r2 = CGRectCreateDictionaryRepresentation(e->userRef);
        if (r1) { m[@"referenceBounds"] = (__bridge NSDictionary *)r1; CFRelease(r1); }
        m[@"semanticSizeType"] = @(e->sizeType);
        if (r2) { m[@"referenceBoundsBeforeOverlapping"] = (__bridge NSDictionary *)r2; CFRelease(r2); }
        m[@"semanticSizeTypeBeforeOverlapping"] = @(e->userType);
        return m;
    }));
    SEL initPlistSel = sel_registerName("initWithPlistRepresentation:");
    gOrigInitPlist = BP2B_Replace(c, "initWithPlistRepresentation:", imp_implementationWithBlock(^id(id me, id plist) {
        id o = gOrigInitPlist ? ((id (*)(id, SEL, id))gOrigInitPlist)(me, initPlistSel, plist) : me;
        if (!o || ![plist isKindOfClass:[NSDictionary class]]) return o;
        NSDictionary *d = plist;
        BP2BAttrExtras *e = [BP2BAttrExtras new];
        CGRect r;
        if ([d[@"referenceBounds"] isKindOfClass:[NSDictionary class]] && CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)d[@"referenceBounds"], &r)) e->sizeRef = r;
        if ([d[@"semanticSizeType"] isKindOfClass:[NSNumber class]]) e->sizeType = [d[@"semanticSizeType"] integerValue];
        if ([d[@"referenceBoundsBeforeOverlapping"] isKindOfClass:[NSDictionary class]] && CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)d[@"referenceBoundsBeforeOverlapping"], &r)) e->userRef = r;
        if ([d[@"semanticSizeTypeBeforeOverlapping"] isKindOfClass:[NSNumber class]]) e->userType = [d[@"semanticSizeTypeBeforeOverlapping"] integerValue];
        if (!BP2B_ExtrasDefault(e)) BP2B_SetExtras(o, e);
        return o;
    }));
    BP_Log(@"[g2b] item1: attributes data model installed (sample hash ok=%d)", sample != nil);
}


// Patch for group2-layout-data.hooks.m BP_G2_ResolveRegionSPI(): after its dlsym block add
//     if (!gRgn.ok) { BP2B_ResolveRegionTable(NO); gRgn.withRect = (void *)BP2B_Rgn.withRect; ... (all 8 fields) ...; gRgn.ok = YES; }
// (the fallback objects are NSObjects and CFAutorelease/CFRelease work on them). Provided as one call so the integrator does not retype it:
static const void *BP2B_RegionTable(void) { BP2B_ResolveRegionTable(NO); return &BP2B_Rgn; }

// =================================================================================================================
// ITEM 3: calculator hook. -[SBDisplayItemLayoutAttributesCalculator _appLayoutByPerformingAutoLayoutIfNeededInAppLayout:...]
// Full replacement of the 160 method (160 0x1c611a81c, 828 insns) by the 162 algorithm (162 0x1c75a4848, 907 insns)
// routed to BP162ChamoisOverlappingController.   DONE (UNSURE items listed in the md)
// =================================================================================================================

static BOOL BP2B_RoleValidForSplitView(long long role) {            // 160 0x1c63e827c: roles 1,2,5,6,7,8,9
    static BOOL (*fn)(long long);
    static dispatch_once_t once;
    dispatch_once(&once, ^{ fn = (BOOL (*)(long long))dlsym(RTLD_DEFAULT, "SBLayoutRoleIsValidForSplitView"); });
    if (fn) return fn(role);
    return role >= 1 && role <= 10 && (((1u << role) & 0xfffffc19u) == 0);
}

// _SBPreferredDisplayItemSizingPolicy(CGSize normalizedSize, long policy, unsigned long supported)   162 0x1c7954330 (decoded)
static long long BP2B_PreferredSizingPolicy(CGSize n, long long policy, unsigned long long supported) {
    BOOL both1 = (n.width == 1.0 && n.height == 1.0);
    long long t = 0;
    if (policy != 2 || both1) t = (policy == 0) ? (both1 ? 2 : 0) : policy;
    if (t != 2 || (supported & 4)) return t;
    return (long long)((supported >> 1) & 1);
}

// 162 -[SBDeviceApplicationSceneHandle _supportedSizingPoliciesForContentOrientation:containerOrientation:] (0x1c76b8534) for 16.0:
// identical to 160 _supportedSizingPolicies (0x1c6227470) but with the two orientations as arguments.
static unsigned long long BP2B_SupportedSizingPolicies(id handle, long long contentO, long long containerO) {
    id ws = BP2B_Obj(handle, @selector(_windowScene));
    id sc = BP2B_Obj(ws, sel_registerName("switcherController"));
    unsigned long long style = (sc && [sc respondsToSelector:sel_registerName("windowManagementStyle")]) ? ((unsigned long long (*)(id, SEL))objc_msgSend)(sc, sel_registerName("windowManagementStyle")) : 0;
    id scene = BP2B_Obj(handle, sel_registerName("sceneIfExists"));
    id settings = BP2B_Obj(scene, @selector(settings));
    id ident = BP2B_Obj(settings, sel_registerName("sb_displayIdentityForSceneManagers"));
    id app = BP2B_Obj(handle, @selector(application));
    SEL s = sel_registerName("supportedSizingPoliciesForSwitcherWindowManagementStyle:displayIdentity:contentOrientation:containerOrientation:");
    if (!app || ![app respondsToSelector:s]) return 0;
    return ((unsigned long long (*)(id, SEL, unsigned long long, id, long long, long long))objc_msgSend)(app, s, style, ident, contentO, containerO);
}

static const void *kBP2B_CalcController = &kBP2B_CalcController;
static id BP2B_PortedController(id calc) {
    id c = calc ? objc_getAssociatedObject(calc, kBP2B_CalcController) : nil;
    if (c) return c;
    Class k = NSClassFromString(@"BP162ChamoisOverlappingController");
    if (!k) return nil;
    c = [k new];
    if (calc && c) objc_setAssociatedObject(calc, kBP2B_CalcController, c, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return c;
}

typedef CGRect (*BP2B_FrameFn)(id, SEL, long long, id, CGRect, long long, id, double, double, BOOL, BOOL, BOOL, BOOL);
static CGRect BP2B_FrameSkipAutoLayout(id calc, long long role, id layout, CGRect bounds, long long orient, id attrs, double dockH, double scale, BOOL ps, BOOL pd) {
    SEL s = sel_registerName("_frameForLayoutRole:inAppLayout:containerBounds:containerOrientation:chamoisLayoutAttributes:floatingDockHeight:screenScale:isChamoisWindowingUIEnabled:prefersStripHidden:prefersDockHidden:skipAutoLayout:");
    if (!calc || ![calc respondsToSelector:s]) return CGRectZero;
    return ((BP2B_FrameFn)objc_msgSend)(calc, s, role, layout, bounds, orient, attrs, dockH, scale, YES, ps, pd, YES);
}

static IMP gOrigAutoLayout;

// The full 162 algorithm.  Returns nil to make the caller fall back to the original 16.0 implementation.
static id BP2B_AutoLayout(id calc, id layout, long long orient, id attrs, double dockH, double scale, id dragging, id before, CGRect bounds, BOOL ps, BOOL pd) {
    if (!calc || !layout || !attrs || bounds.size.width <= 0 || bounds.size.height <= 0) return nil;
    id controller = BP2B_PortedController(calc);
    Class keyClass = NSClassFromString(@"SBAppLayoutOverlappingModelCacheKey");
    Class modelClass = NSClassFromString(@"SBChamoisOverlappingModel");
    id grid = BP2B_Obj(calc, sel_registerName("_chamoisLayoutGridCache"));
    if (!controller || !keyClass || !modelClass || !grid) return nil;
    SEL keySel = sel_registerName("cacheKeyForSnapshotOfAppLayout:containerBounds:containerOrientation:floatingDockHeight:hideStrips:hideDock:draggingItem:");
    if (!class_getClassMethod(keyClass, keySel)) return nil;                       // group 2 cache key shim missing
    typedef id (*KeyFn)(Class, SEL, id, CGRect, long long, double, BOOL, BOOL, id);
    #define BP2B_KEY(l) ((KeyFn)objc_msgSend)(keyClass, keySel, (l), bounds, orient, dockH, ps, pd, dragging)

    // (1) cache check
    id lastKey = BP2B_Obj(layout, sel_registerName("cachedLastOverlappingModelKey"));
    id key = BP2B_KEY(layout);
    if (lastKey && key && [lastKey isEqual:key]) return layout;

    // (2) grid limits
    CGSize defSize = BP2B_Size(attrs, sel_registerName("defaultWindowSize"));
    double pad = BP2B_Dbl(attrs, sel_registerName("screenEdgePadding"));
    double maxW = BP2B_Dbl(attrs, sel_registerName("maximumWindowWidthForOverlapping"));
    Class infoClass = NSClassFromString(@"SBDisplayItemGridLayoutRestrictionInfo");
    SEL infoSel = sel_registerName("layoutRestrictionInfoWithLayoutRestrictions:restrictedSize:");
    SEL gridSel = sel_registerName("nearestGridSizeForProposedSize:inBounds:contentOrientation:layoutRestrictionInfo:screenScale:chamoisLayoutAttributes:");
    if (!infoClass || !class_getClassMethod(infoClass, infoSel) || ![grid respondsToSelector:gridSel]) return nil;
    id info = ((id (*)(Class, SEL, unsigned long long, CGSize))objc_msgSend)(infoClass, infoSel, 0, CGSizeMake(-1.0, -1.0));
    CGSize gridMax = ((CGSize (*)(id, SEL, CGSize, CGRect, long long, id, double, id))objc_msgSend)(grid, gridSel, CGSizeMake(maxW, bounds.size.height), bounds, orient, info, scale, attrs);

    SEL allItemsS = sel_registerName("allItems"), roleS = sel_registerName("layoutRoleForItem:"), attrsS = sel_registerName("layoutAttributesForItem:");
    SEL modS = sel_registerName("appLayoutByModifyingLayoutAttributes:forItem:");
    SEL userS = sel_registerName("userSizeBeforeOverlappingInBounds:defaultSize:screenEdgePadding:");
    if (![layout respondsToSelector:modS] || ![layout respondsToSelector:attrsS] || ![layout respondsToSelector:roleS]) return nil;
    NSArray *all = BP2B_Obj(layout, allItemsS);
    id cur = layout;

    // (3) pre-pass over the user-configured-size-before-overlapping (162 0x1c75a4a1c..0x1c75a4ecc)
    if (all.count >= 2) {
        for (id item in all) {
            long long role = ((long long (*)(id, SEL, id))objc_msgSend)(cur, roleS, item);
            if (!BP2B_RoleValidForSplitView(role)) continue;
            id a = BP2B_Obj1(cur, attrsS, item);
            if (!a) continue;
            CGSize us = BP2B_AttrsUserSizeInBounds(a, bounds, defSize, pad);
            if (!(us.width == 0 && us.height == 0)) continue;                      // only windows that never recorded one
            CGRect f = BP2B_FrameSkipAutoLayout(calc, role, cur, bounds, orient, attrs, dockH, scale, ps, pd);
            BP2BAttrSize inferUser = BP2B_AttrSizeInfer(f.size, bounds, defSize, pad);
            id a2 = ((id (*)(id, SEL, BP2BAttrSize))objc_msgSend)(a, sel_registerName("attributesByModifyingAttributedUserSizeBeforeOverlapping:"), inferUser);
            if (!a2) a2 = a;
            if (BP2B_FGT(f.size.width, gridMax.width) || BP2B_FGT(f.size.height, gridMax.height)) {
                CGSize c = CGSizeMake(fmin(gridMax.width, f.size.width), fmin(gridMax.height, f.size.height));
                BP2BAttrSize inferSize = BP2B_AttrSizeInfer(c, bounds, defSize, pad);
                id a3 = ((id (*)(id, SEL, BP2BAttrSize))objc_msgSend)(a2, sel_registerName("attributesByModifyingAttributedSize:"), inferSize);
                if (a3) a2 = a3;
            }
            id n = ((id (*)(id, SEL, id, id))objc_msgSend)(cur, modS, a2, item);
            if (n) cur = n;
        }
    } else if (all.count == 1) {
        SEL ifr = sel_registerName("itemForLayoutRole:");
        id item = ((id (*)(id, SEL, long long))objc_msgSend)(cur, ifr, 1);
        id a = item ? BP2B_Obj1(cur, attrsS, item) : nil;
        if (a) {
            CGSize us = BP2B_AttrsUserSizeInBounds(a, bounds, defSize, pad);
            if (!(us.width == 0 && us.height == 0)) {
                id a2 = a;
                if (BP2B_FGT(us.width, gridMax.width) || BP2B_FGT(us.height, gridMax.height)) {
                    BP2BAttrSize inf = BP2B_AttrSizeInfer(us, bounds, defSize, pad);
                    id a3 = ((id (*)(id, SEL, BP2BAttrSize))objc_msgSend)(a, sel_registerName("attributesByModifyingAttributedSize:"), inf);
                    if (a3) a2 = a3;
                }
                BP2BAttrSize unspec = BP2B_AttrSizeUnspecified();
                id a4 = ((id (*)(id, SEL, BP2BAttrSize))objc_msgSend)(a2, sel_registerName("attributesByModifyingAttributedUserSizeBeforeOverlapping:"), unspec);
                if (a4) a2 = a4;
                id n = ((id (*)(id, SEL, id, id))objc_msgSend)(cur, modS, a2, item);
                if (n) cur = n;
            }
        }
    }
    id layout2 = cur;

    // (4) z-ordered valid items -> preferred model
    NSMutableArray *valid = [NSMutableArray array];
    SEL enumS = sel_registerName("enumerate:");
    if (![layout2 respondsToSelector:enumS]) return nil;
    ((void (*)(id, SEL, void (^)(long long, id, BOOL *)))objc_msgSend)(layout2, enumS, ^(long long role, id item, BOOL *stop) {
        if (BP2B_RoleValidForSplitView(role) && item) [valid addObject:item];
    });
    NSArray *zo = BP2B_Obj(layout2, sel_registerName("zOrderedItems")) ?: @[];
    [valid sortUsingComparator:^NSComparisonResult(id x, id y) {
        return [@([zo indexOfObject:x]) compare:@([zo indexOfObject:y])];
    }];
    NSMutableDictionary *centers = [NSMutableDictionary dictionary], *sizes = [NSMutableDictionary dictionary];
    for (id item in valid) {
        long long role = ((long long (*)(id, SEL, id))objc_msgSend)(layout2, roleS, item);
        CGRect f = BP2B_FrameSkipAutoLayout(calc, role, layout2, bounds, orient, attrs, dockH, scale, ps, pd);
        centers[item] = [NSValue valueWithCGPoint:CGPointMake(CGRectGetMidX(f), CGRectGetMidY(f))];
        sizes[item] = [NSValue valueWithCGSize:f.size];
    }
    id model = [modelClass alloc];
    SEL init4 = sel_registerName("initWithItems:centersForItems:sizesForItems:containerBounds:");
    SEL init6 = sel_registerName("initWithItems:centersForItems:sizesForItems:userConfiguredSizesBeforeAutoResizingForItems:containerBounds:boundingBox:");
    if ([model respondsToSelector:init4]) {
        model = ((id (*)(id, SEL, id, id, id, CGRect))objc_msgSend)(model, init4, valid, centers, sizes, bounds);
    } else if ([model respondsToSelector:init6]) {
        model = ((id (*)(id, SEL, id, id, id, id, CGRect, CGRect))objc_msgSend)(model, init6, valid, centers, sizes, @{}, bounds, CGRectZero);
    } else {
        return nil;
    }
    if (!model) return nil;

    // (5) the ported controller
    SEL ctl = sel_registerName("modelByPerformingAutoLayoutForModel:chamoisLayoutAttributes:draggingItem:modelBeforeDragging:floatingDockHeight:bounds:screenScale:prefersStripHidden:prefersDockHidden:");
    if (![controller respondsToSelector:ctl]) return nil;
    id result = ((id (*)(id, SEL, id, id, id, id, double, CGRect, double, BOOL, BOOL))objc_msgSend)(controller, ctl, model, attrs, dragging, before, dockH, bounds, scale, ps, pd);
    if (!result) result = model;                                                   // the controller refuses (e.g. no region SPI) -> keep the preferred model

    // (6) write back (162 0x1c75a51c8..0x1c75a54f0)
    NSMutableDictionary *newAttrs = [NSMutableDictionary dictionary];
    SEL itemsS = @selector(items), centerS = sel_registerName("centerForItem:"), sizeS = sel_registerName("sizeForItem:");
    SEL peekS = sel_registerName("unoccludedPeekingCenterForItem:"), fullS = sel_registerName("isItemFullyOccluded:"), partS = sel_registerName("isItemPartiallyOccluded:");
    if (![result respondsToSelector:peekS]) peekS = sel_registerName("fullyOccludedPeekingCenterForItem:");
    NSArray *mitems = BP2B_Obj(result, itemsS) ?: @[];
    for (id item in mitems) {
        CGPoint c = ((CGPoint (*)(id, SEL, id))objc_msgSend)(result, centerS, item);
        CGSize sz = ((CGSize (*)(id, SEL, id))objc_msgSend)(result, sizeS, item);
        CGPoint peek = [result respondsToSelector:peekS] ? ((CGPoint (*)(id, SEL, id))objc_msgSend)(result, peekS, item) : CGPointZero;
        long long occ = BP2B_Bool1(result, fullS, item) ? 3 : (BP2B_Bool1(result, partS, item) ? 2 : 1);
        id a = BP2B_Obj1(layout2, attrsS, item);
        if (!a) continue;
        CGSize nSize = CGSizeMake(sz.width / bounds.size.width, sz.height / bounds.size.height);        // normalizedSizeForSize:inBounds:
        CGPoint nC = CGPointMake(c.x / bounds.size.width, c.y / bounds.size.height);
        CGPoint nPeek = CGPointMake(peek.x / bounds.size.width, peek.y / bounds.size.height);
        long long policy = BP2B_LL(a, @selector(sizingPolicy));
        id handle = BP2B_Obj1(calc, sel_registerName("_deviceApplicationSceneHandleForDisplayItem:"), item);
        if (handle) {
            unsigned long long sup = BP2B_SupportedSizingPolicies(handle, BP2B_LL(a, sel_registerName("contentOrientation")), orient);
            policy = BP2B_PreferredSizingPolicy(nSize, policy, sup);
        }
        id a1 = ((id (*)(id, SEL, long long))objc_msgSend)(a, sel_registerName("attributesByModifyingSizingPolicy:"), policy) ?: a;
        id a2 = ((id (*)(id, SEL, CGPoint))objc_msgSend)(a1, sel_registerName("attributesByModifyingNormalizedCenter:"), nC) ?: a1;
        id a3 = ((id (*)(id, SEL, long long))objc_msgSend)(a2, sel_registerName("attributesByModifyingOcclusionState:"), occ) ?: a2;
        id a4 = ((id (*)(id, SEL, CGPoint))objc_msgSend)(a3, sel_registerName("attributesByModifyingUnoccludedPeekingCenter:"), nPeek) ?: a3;
        BP2BAttrSize as = BP2B_GetAttributedSize(a4);
        if (BP2B_AttrSizeIsUnspecified(as) || CGRectIsNull(as.referenceBounds) || CGRectIsEmpty(as.referenceBounds)) {
            BP2BAttrSize inf = BP2B_AttrSizeInfer(sz, bounds, defSize, pad);
            id a5 = ((id (*)(id, SEL, BP2BAttrSize))objc_msgSend)(a4, sel_registerName("attributesByModifyingAttributedSize:"), inf);
            if (a5) a4 = a5;
        }
        newAttrs[item] = a4;
    }
    id layout3 = ((id (*)(id, SEL, id))objc_msgSend)(layout2, sel_registerName("appLayoutByModifyingLayoutAttributesForItems:"), newAttrs) ?: layout2;
    if ([layout3 respondsToSelector:sel_registerName("setCachedLastOverlappingModel:")])
        ((void (*)(id, SEL, id))objc_msgSend)(layout3, sel_registerName("setCachedLastOverlappingModel:"), result);
    id key2 = BP2B_KEY(layout2);                                                   // key of the layout BEFORE the attribute write-back, as 162 0x1c75a554c does (x19 = [sp,#0x68])
    if (key2 && [layout3 respondsToSelector:sel_registerName("setCachedLastOverlappingModelKey:")])
        ((void (*)(id, SEL, id))objc_msgSend)(layout3, sel_registerName("setCachedLastOverlappingModelKey:"), key2);
    #undef BP2B_KEY
    return layout3;
}

static void BP2B_SetupCalculator(void) {
    Class c = objc_getClass("SBDisplayItemLayoutAttributesCalculator");
    if (!c) return;
    // supported-policies shim (162 name) on the scene handle
    Class h = objc_getClass("SBDeviceApplicationSceneHandle");
    if (h) BP2B_AddIfMissing(h, "_supportedSizingPoliciesForContentOrientation:containerOrientation:",
                             imp_implementationWithBlock(^unsigned long long(id me, long long co, long long cn) { return BP2B_SupportedSizingPolicies(me, co, cn); }), "Q32@0:8q16q24");
    // 162 calculator additions that ported callers use
    BP2B_AddIfMissing(c, "_applicationForDisplayItem:", imp_implementationWithBlock(^id(id me, id item) {
        id bid = BP2B_Obj(item, @selector(bundleIdentifier));
        Class ac = NSClassFromString(@"SBApplicationController");
        id shared = BP2B_Obj((id)ac, @selector(sharedInstance));
        return bid ? BP2B_Obj1(shared, sel_registerName("applicationWithBundleIdentifier:"), bid) : nil;
    }), "@24@0:8@16");

    SEL autoSel = sel_registerName("_appLayoutByPerformingAutoLayoutIfNeededInAppLayout:containerOrientation:chamoisLayoutAttributes:floatingDockHeight:screenScale:draggingItem:overlappingModelBeforeDragging:bounds:prefersStripHidden:prefersDockHidden:");
    Method m = class_getInstanceMethod(c, autoSel);
    if (!m) { BP_Log(@"[g2b] item3: calculator auto-layout method not found"); return; }
    gOrigAutoLayout = BP2B_Replace(c, "_appLayoutByPerformingAutoLayoutIfNeededInAppLayout:containerOrientation:chamoisLayoutAttributes:floatingDockHeight:screenScale:draggingItem:overlappingModelBeforeDragging:bounds:prefersStripHidden:prefersDockHidden:",
        imp_implementationWithBlock(^id(id me, id layout, long long orient, id attrs, double dockH, double scale, id dragging, id before, CGRect bounds, BOOL ps, BOOL pd) {
            typedef id (*Orig)(id, SEL, id, long long, id, double, double, id, id, CGRect, BOOL, BOOL);
            id r = BP2B_Enabled("g2b") ? BP2B_AutoLayout(me, layout, orient, attrs, dockH, scale, dragging, before, bounds, ps, pd) : nil;
            if (r) return r;
            return gOrigAutoLayout ? ((Orig)gOrigAutoLayout)(me, autoSel, layout, orient, attrs, dockH, scale, dragging, before, bounds, ps, pd) : layout;
        }));
    // context wrapper around the 16.0 frame computation (see gBP2B_Ctx)
    {
        static IMP origFrame;
        SEL fs = sel_registerName("_frameForLayoutRole:inAppLayout:containerBounds:containerOrientation:chamoisLayoutAttributes:floatingDockHeight:screenScale:isChamoisWindowingUIEnabled:prefersStripHidden:prefersDockHidden:skipAutoLayout:");
        origFrame = BP2B_Replace(c, "_frameForLayoutRole:inAppLayout:containerBounds:containerOrientation:chamoisLayoutAttributes:floatingDockHeight:screenScale:isChamoisWindowingUIEnabled:prefersStripHidden:prefersDockHidden:skipAutoLayout:",
            imp_implementationWithBlock(^CGRect(id me, long long role, id layout, CGRect bounds, long long orient, id attrs, double dockH, double scale, BOOL chamois, BOOL ps, BOOL pd, BOOL skip) {
                if (!origFrame) return CGRectZero;
                typedef CGRect (*F)(id, SEL, long long, id, CGRect, long long, id, double, double, BOOL, BOOL, BOOL, BOOL);
                __typeof__(gBP2B_Ctx) saved = gBP2B_Ctx;
                if (chamois && attrs && BP2B_Enabled("g2b")) {
                    gBP2B_Ctx.on = YES;
                    gBP2B_Ctx.def = BP2B_Size(attrs, sel_registerName("defaultWindowSize"));
                    gBP2B_Ctx.pad = BP2B_Dbl(attrs, sel_registerName("screenEdgePadding"));
                }
                CGRect r = ((F)origFrame)(me, fs, role, layout, bounds, orient, attrs, dockH, scale, chamois, ps, pd, skip);
                gBP2B_Ctx = saved;
                return r;
            }));
    }
    // every user of the old controller getter now gets the ported controller (the 160 controller class is never used again)
    SEL getS = sel_registerName("_chamoisOverlappingControllerCache");
    if (class_getInstanceMethod(c, getS) && NSClassFromString(@"BP162ChamoisOverlappingController"))
        BP2B_Replace(c, "_chamoisOverlappingControllerCache", imp_implementationWithBlock(^id(id me) { return BP2B_PortedController(me); }));
    BP_Log(@"[g2b] item3: calculator auto layout replaced");
}


// =================================================================================================================
// ITEM 2: -[SBFluidSwitcherViewController _layoutAppLayout:roleMask:completion:] (+ its 31 blocks)
// Reconstruction of 162 0x1c74431b0 / block 0x1c744326c (2639 insns) / blocks _2.._31 (0x1c7445ba8..0x1c7446bdc),
// cross-checked against 160 0x1c5fca458 / 0x1c5fca514 (2577 insns).   See md ITEM 2.
// Policy (md 2.4): full port of the Stage Manager (chamois) path; the classic switcher (chamois off) and the three
// pin/rotation/in-flight-anchor-adoption situations run the saved original 16.0 IMP unchanged.
// =================================================================================================================

typedef struct { double tl, bl, br, tr; } BP2BRadii;            // UIRectCornerRadii (HFA of 4 doubles)
typedef void (^BP2BDone)(BOOL, BOOL);
typedef BP2BDone (^BP2BMaker)(NSString *);

static IMP gOrigLayoutAppLayout;

static BOOL BP2B_RoleMaskContains(unsigned long long mask, long long role) {
    static BOOL (*fn)(unsigned long long, long long); static dispatch_once_t once;
    dispatch_once(&once, ^{ fn = (BOOL (*)(unsigned long long, long long))dlsym(RTLD_DEFAULT, "SBLayoutRoleMaskContainsRole"); });
    if (fn) return fn(mask, role);
    return role >= 0 && role < 64 && ((mask >> role) & 1);
}
static void BP2B_EnumerateValidRoles(void (^blk)(long long)) {
    static void (*fn)(void (^)(long long)); static dispatch_once_t once;
    dispatch_once(&once, ^{ fn = (void (*)(void (^)(long long)))dlsym(RTLD_DEFAULT, "SBLayoutRoleEnumerateValidRoles"); });
    if (fn) { fn(blk); return; }
    for (long long r = 1; r <= 9; r++) if (BP2B_RoleValidForSplitView(r)) blk(r);
}
static CGRect BP2B_RectWithSize(double w, double h) { return CGRectMake(0, 0, w, h); }            // SBRectWithSize

#define BP2B_S0(RET, o, sel) ((RET (*)(id, SEL))objc_msgSend)((o), sel_registerName(sel))
#define BP2B_S1(RET, o, sel, a) ((RET (*)(id, SEL, __typeof__(a)))objc_msgSend)((o), sel_registerName(sel), (a))
#define BP2B_S2(RET, o, sel, a, b) ((RET (*)(id, SEL, __typeof__(a), __typeof__(b)))objc_msgSend)((o), sel_registerName(sel), (a), (b))
#define BP2B_S3(RET, o, sel, a, b, c) ((RET (*)(id, SEL, __typeof__(a), __typeof__(b), __typeof__(c)))objc_msgSend)((o), sel_registerName(sel), (a), (b), (c))
#define BP2B_S4(RET, o, sel, a, b, c, d) ((RET (*)(id, SEL, __typeof__(a), __typeof__(b), __typeof__(c), __typeof__(d)))objc_msgSend)((o), sel_registerName(sel), (a), (b), (c), (d))

// 160 and 162 both apply the animation through +[UIView sb_animateWithSettings:mode:animations:completion:]
static void BP2B_Animate(id settings, long long mode, void (^anims)(void), void (^completion)(BOOL, BOOL)) {
    Class ui = [UIView class];
    SEL s = sel_registerName("sb_animateWithSettings:mode:animations:completion:");
    if (settings && [ui respondsToSelector:s])
        ((void (*)(Class, SEL, id, long long, void (^)(void), void (^)(BOOL, BOOL)))objc_msgSend)(ui, s, settings, mode, anims, completion);
    else {                                                                                     // no settings: apply without animation
        anims();
        if (completion) completion(YES, NO);
    }
}

// An "animatable property with notifications" (resize / reposition progress): set to 1.0 inside the animation, invalidated in the completion.
static id BP2B_ProgressProperty(id vc, id notifications, NSString *eventClassName) {
    if (![notifications respondsToSelector:@selector(count)] || [(NSArray *)notifications count] == 0) return nil;
    Class ev = NSClassFromString(eventClassName);
    SEL s = sel_registerName("_animatablePropertyWithNotifications:progressEventType:");
    if (!ev || ![vc respondsToSelector:s]) return nil;
    return ((id (*)(id, SEL, id, Class))objc_msgSend)(vc, s, notifications, ev);
}
static void BP2B_SetProp(id prop, double v) { if (prop && [prop respondsToSelector:@selector(setValue:)]) ((void (*)(id, SEL, double))objc_msgSend)(prop, @selector(setValue:), v); }
static void (^BP2B_CompletionFor(id prop, BP2BDone maker))(BOOL, BOOL) {                           // blocks _11/_20/_22/_24: [prop invalidate]; maker(finished, retargeted)
    return ^(BOOL f, BOOL r) {
        if (prop && [prop respondsToSelector:@selector(invalidate)]) ((void (*)(id, SEL))objc_msgSend)(prop, @selector(invalidate));
        if (maker) maker(f, r);
    };
}

// Does any property animation with one of the given key paths run on the layer? (the 0x1e18eb1e0/200/220/240 test blocks)
static BOOL BP2B_LayerHasModifier(id layer, NSArray<NSString *> *keyPaths) {
    NSArray *mods = BP2B_Obj(layer, sel_registerName("presentationModifiers"));
    for (id m in mods) {
        NSString *kp = BP2B_Obj(m, sel_registerName("keyPath"));
        if ([kp isKindOfClass:[NSString class]] && [keyPaths containsObject:kp]) return YES;
    }
    return NO;
}

static void BP2B_LayoutAppLayoutImpl(id vc, SEL cmd, id appLayout, unsigned long long roleMask, id completion) {
    typedef void (*Orig)(id, SEL, id, unsigned long long, id);
    #define BP2B_FALLBACK() do { if (gOrigLayoutAppLayout) ((Orig)gOrigLayoutAppLayout)(vc, cmd, appLayout, roleMask, completion); return; } while (0)
    if (!appLayout || !BP2B_Enabled("g2blayout")) BP2B_FALLBACK();
    id root = BP2B_IvarObj(vc, "_rootModifier");
    if (!root || !BP2B_Bool(vc, sel_registerName("isChamoisWindowingUIEnabled"))) BP2B_FALLBACK();         // classic switcher: 16.0 code unchanged
    NSArray *aps = BP2B_Obj(vc, sel_registerName("appLayouts"));
    NSUInteger idx = aps ? [aps indexOfObject:appLayout] : NSNotFound;
    BOOL rotationAnim = BP2B_Bool(root, sel_registerName("shouldPerformRotationAnimationForOrientationChange"));
    if (idx != NSNotFound) {
        if (rotationAnim) BP2B_FALLBACK();
        SEL pinS = sel_registerName("shouldPinLayoutRolesToSpace:");
        if ([root respondsToSelector:pinS] && ((BOOL (*)(id, SEL, NSUInteger))objc_msgSend)(root, pinS, idx)) BP2B_FALLBACK();
    }
    Class group = NSClassFromString(@"SBC2GroupCompletion");
    SEL performS = sel_registerName("perform:finalCompletion:options:delegate:");
    if (!group || !class_getClassMethod(group, performS)) BP2B_FALLBACK();

    long long contentOrientation = 0;
    BP2B_IvarGet(vc, "_contentOrientation", &contentOrientation, sizeof contentOrientation);
    NSDictionary *adjustedMap = BP2B_IvarObj(vc, "_leafAppLayoutsToAdjustedAppLayouts");
    NSDictionary *liveOverlays = BP2B_IvarObj(vc, "_liveContentOverlays");
    NSDictionary *overlayViews = BP2B_IvarObj(vc, "_visibleOverlayAccessoryViews");
    NSDictionary *underlayViews = BP2B_IvarObj(vc, "_visibleUnderlayAccessoryViews");
    Class uiViewClass = [UIView class];
    (void)uiViewClass;

    void (^body)(BP2BMaker) = ^(BP2BMaker make) {
        if (idx == NSNotFound) return;
        // ---- (1) queries by index (162 0x1c74432f8..0x1c7443840) ----------------------------------------------------------------
        CGPoint anchor = BP2B_S1(CGPoint, root, "anchorPointForIndex:", (NSUInteger)(idx));
        CGRect frame = BP2B_S1(CGRect, root, "frameForIndex:", (NSUInteger)(idx));
        double S = BP2B_S1(double, root, "scaleForIndex:", (NSUInteger)(idx));
        double rotation = BP2B_S1(double, root, "rotationAngleForIndex:", (NSUInteger)(idx));
        BP2BRadii radii = BP2B_S1(BP2BRadii, root, "cornerRadiiForIndex:", (NSUInteger)(idx));
        double minKill = BP2B_S1(double, root, "minimumTranslationToKillIndex:", (NSUInteger)(idx));
        double pageScale = BP2B_S2(double, root, "contentPageViewScaleForAppLayout:withScale:", (id)(appLayout), (double)(S));
        BOOL overlayFill = BP2B_S1(BOOL, root, "shouldScaleOverlayToFillBoundsAtIndex:", (NSUInteger)(idx));
        BOOL contentFill = BP2B_S1(BOOL, root, "shouldScaleContentToFillBoundsAtIndex:", (NSUInteger)(idx));
        CGRect clipIdx = BP2B_S2(CGRect, root, "clippingFrameForIndex:withBounds:", (NSUInteger)(idx), (CGRect)(BP2B_RectWithSize(frame.size.width, frame.size.height)));
        BOOL clips = BP2B_S1(BOOL, root, "clipsToBoundsAtIndex:", (NSUInteger)(idx));
        unsigned long long maskedCorners = BP2B_S1(unsigned long long, root, "maskedCornersForIndex:", (NSUInteger)(idx));
        double perspective = BP2B_S1(double, root, "perspectiveAngleForAppLayout:", (id)(appLayout));
        id mesh = BP2B_S1(id, root, "meshTransformForIndex:", (NSUInteger)(idx));
        // home-affordance counter rotation of the accessory home grabber
        CATransform3D homeT = CATransform3DIdentity;
        {
            SEL bs = sel_registerName("_bestSupportedHomeAffordanceOrientationForOrientation:inAppLayout:");
            if ([vc respondsToSelector:bs]) {
                long long best = ((long long (*)(id, SEL, long long, id))objc_msgSend)(vc, bs, contentOrientation, appLayout);
                static double (*angleFn)(long long, long long); static dispatch_once_t o2;
                dispatch_once(&o2, ^{ angleFn = (double (*)(long long, long long))dlsym(RTLD_DEFAULT, "SBFAngleForRotationFromInterfaceOrientationToInterfaceOrientation"); });
                if (best != contentOrientation && angleFn) homeT = CATransform3DMakeRotation(angleFn(contentOrientation, best), 0, 0, 1);
            }
        }
        id grabberAttrs = BP2B_S1(id, root, "resizeGrabberLayoutAttributesForAppLayout:", (id)(appLayout));
        id grabberLeaf = BP2B_Obj(grabberAttrs, sel_registerName("leafAppLayout"));
        id adjusted = grabberLeaf ? adjustedMap[grabberLeaf] : nil;
        CGRect grabberRect = CGRectNull;
        if (adjusted) {
            id gi = BP2B_S1(id, grabberLeaf, "itemForLayoutRole:", (long long)(1));
            long long gr = ((long long (*)(id, SEL, id))objc_msgSend)(adjusted, sel_registerName("layoutRoleForItem:"), gi);
            CGRect sf = BP2B_S3(CGRect, root, "frameForLayoutRole:inAppLayout:withBounds:", (long long)(gr), (id)(adjusted), (CGRect)(BP2B_RectWithSize(frame.size.width, frame.size.height)));
            double sepW = BP2B_Dbl(vc, sel_registerName("separatorViewWidth"));
            long long edge = BP2B_LL(grabberAttrs, sel_registerName("edge"));
            double gx = (edge == 2) ? CGRectGetMinX(sf) - sepW : CGRectGetMaxX(sf);
            grabberRect = CGRectMake(gx, CGRectGetMinY(sf), sepW, CGRectGetHeight(sf));          // UNSURE: width is separatorViewWidth (0x58 slot)
        }
        BOOL perspectiveIsZero = fabs(perspective) < 1e-9;                                      // _BSFloatIsZero
        CGPoint accOffset = BP2B_S1(CGPoint, root, "contentViewOffsetForAccessoriesOfAppLayout:", (id)(appLayout));
        unsigned long long multiMask = BP2B_S1(unsigned long long, root, "multipleWindowsIndicatorLayoutRoleMaskForAppLayout:", (id)(appLayout));
        BOOL wallpaperTreatment = BP2B_Bool(root, sel_registerName("shouldUseWallpaperGradientTreatment"));
        struct { double a, b; } grad = BP2B_S1(__typeof__(grad), root, "wallpaperGradientAttributesForIndex:", (NSUInteger)(idx));
        id attrsObj = BP2B_Obj1(root, sel_registerName("animationAttributesForLayoutElement:"), appLayout);
        #define AM(sel) BP2B_LL(attrsObj, sel_registerName(sel))
        long long updateMode = AM("updateMode");
        #define MODE(sel) ({ long long m_ = AM(sel); m_ ? m_ : updateMode; })
        long long layoutMode = MODE("layoutUpdateMode"), positionMode = MODE("positionUpdateMode"), scaleMode = MODE("scaleUpdateMode");
        long long cornerMode = MODE("cornerRadiusUpdateMode"), clippingMode = MODE("clippingUpdateMode"), meshMode = MODE("meshUpdateMode");
        long long opacityMode = MODE("opacityUpdateMode");
        id layoutSettings = BP2B_Obj(attrsObj, sel_registerName("layoutSettings"));
        #define ST(sel) ({ id s_ = BP2B_Obj(attrsObj, sel_registerName(sel)); s_ ?: layoutSettings; })
        id positionSettings = ST("positionSettings"), scaleSettings = ST("scaleSettings"), cornerSettings = ST("cornerRadiusSettings");
        id clippingSettings = ST("clippingSettings"), meshSettings = ST("meshSettings"), opacitySettings = ST("opacitySettings");

        NSArray *leafs = BP2B_Obj(appLayout, sel_registerName("leafAppLayouts")) ?: @[];
        double minRadius = fmin(fmin(fmin(radii.tl, radii.bl), radii.br), radii.tr);
        double bw = frame.size.width, bh = frame.size.height;
        double ancX = anchor.x * bw, ancY = anchor.y * bh;                                       // [sp,#0xb8] / [sp,#0x118]
        double baseX = frame.origin.x + (0.5 - anchor.x) * bw;                                   // [sp,#0xe8]
        double baseY = frame.origin.y + (0.5 - anchor.y) * bh;                                   // [sp,#0xd0]
        double gradDelta = grad.a - grad.b;
        CGRect lastR = CGRectZero;
        double lastAdjScale = S; BOOL accessoriesRan = NO;

        // ---- (2) per leaf (162 0x1c74439b8..0x1c7445228) ---------------------------------------------------------------------------
        for (id leaf in leafs) {
            id item0 = [[BP2B_Obj(leaf, sel_registerName("allItems")) ?: @[] ] firstObject];
            long long role = ((long long (*)(id, SEL, id))objc_msgSend)(appLayout, sel_registerName("layoutRoleForItem:"), item0);
            if (!BP2B_RoleMaskContains(roleMask, role)) continue;
            id c = BP2B_Obj1(vc, sel_registerName("_itemContainerForAppLayoutIfExists:"), leaf);
            if (!c) continue;
            // role frame / scale / clipping from the root modifier
            CGRect R = BP2B_S3(CGRect, root, "frameForLayoutRole:inAppLayout:withBounds:", (long long)(role), (id)(appLayout), (CGRect)(BP2B_RectWithSize(bw, bh)));
            double roleScale = BP2B_S2(double, root, "scaleForLayoutRole:inAppLayout:", (long long)(role), (id)(appLayout));
            CGRect clip = BP2B_S4(CGRect, root, "clippingFrameForLayoutRole:inAppLayout:atIndex:withBounds:", (long long)(role), (id)(appLayout), (NSUInteger)(idx), (CGRect)(BP2B_RectWithSize(bw, bh)));
            lastR = R;
            // position math (the A region): pin == NO on this path, so the anchor applied is the index anchor and no compensation translation exists
            double dx = 0.5 - anchor.x, dy = 0.5 - anchor.y;
            double X = (baseX + R.origin.x) - R.size.width * dx;
            double Y = (baseY + R.origin.y) - R.size.height * dy;
            X += S * (1.0 - roleScale) * (R.size.width * dx);                                    // chamois term (isChamoisWindowingUIEnabled == YES here)
            Y += S * (1.0 - roleScale) * (R.size.height * dy);
            double layerScale = S * roleScale;                                                   // [sp,#0x2f8]
            CGPoint anchorApplied = anchor;
            // cornerRadii / maskedCorners / blur / drag per role
            BP2BRadii rr = BP2B_S3(BP2BRadii, root, "cornerRadiiForLayoutRole:inAppLayout:withCornerRadii:", (long long)(role), (id)(appLayout), (BP2BRadii)(radii));
            unsigned long long mc = BP2B_S3(unsigned long long, root, "maskedCornersForLayoutRole:inAppLayout:withMaskedCorners:", (long long)(role), (id)(appLayout), (unsigned long long)(maskedCorners));
            BOOL blurred = BP2B_S2(BOOL, root, "isLayoutRoleBlurred:inAppLayout:", (long long)(role), (id)(appLayout));
            long long blurTarget = BP2B_S2(long long, root, "blurTargetPreferenceForLayoutRole:inAppLayout:", (long long)(role), (id)(appLayout));
            BOOL canDnD = BP2B_S2(BOOL, root, "canLayoutRoleParticipateInSwitcherDragAndDrop:appLayout:", (long long)(role), (id)(appLayout));
            BOOL draggable = BP2B_S2(BOOL, root, "isLayoutRoleDraggable:inAppLayout:", (long long)(role), (id)(appLayout));
            BOOL nonuniform = BP2B_S2(BOOL, root, "shouldUseNonuniformSnapshotScalingForLayoutRole:inAppLayout:", (long long)(role), (id)(appLayout));
            double blurDelay = BP2B_S2(double, root, "blurDelayForLayoutRole:inAppLayout:", (long long)(role), (id)(appLayout));
            double blurIcon = BP2B_S1(double, root, "blurViewIconScaleForIndex:", (NSUInteger)(idx));
            CGPoint pageOffset = BP2B_S2(CGPoint, root, "contentViewOffsetForLayoutRole:inAppLayout:", (long long)(role), (id)(appLayout));
            BOOL tether = BP2B_S1(BOOL, root, "shouldTetherItemsAndAccessoriesInAppLayout:", (id)(appLayout));
            double pageAnchorX = tether ? ((bw * 0.5) - R.origin.x) / R.size.width : 0.5;        // [sp,#0x278]
            id live = liveOverlays[leaf];
            // progress properties: only when the size / centre really change
            id resizeProp = nil, repositionProp = nil;
            CGRect cb = BP2B_Rect(c, @selector(bounds));
            if (!(R.size.width == cb.size.width && R.size.height == cb.size.height))
                resizeProp = BP2B_ProgressProperty(vc, BP2B_S2(id, root, "resizeProgressNotificationsForLayoutRole:inAppLayout:", (long long)(role), (id)(appLayout)), @"SBResizeProgressSwitcherModifierEvent");
            CGPoint cc = BP2B_Point(c, @selector(center));
            CGPoint newC = CGPointMake(X + R.size.width * 0.5, Y + R.size.height * 0.5);        // UIRectGetCenter(X, Y, Rw, Rh)
            if (!(cc.x == newC.x && cc.y == newC.y))
                repositionProp = BP2B_ProgressProperty(vc, BP2B_S2(id, root, "repositionProgressNotificationsForLayoutRole:inAppLayout:", (long long)(role), (id)(appLayout)), @"SBRepositionProgressSwitcherModifierEvent");
            BOOL legacyRot = rotationAnim ? BP2B_Bool1(vc, sel_registerName("_appLayoutRequiresLegacyRotationSupport:"), appLayout) : NO;
            // plain container setters (outside any animation)
            BP2B_S1(void, c, "setShouldScaleOverlayToFillBounds:", (BOOL)(overlayFill));
            BP2B_S1(void, c, "setPositionAnimationsBeginFromModelState:", (BOOL)(rotationAnim));
            BP2B_S1(void, c, "setTransformAnimationsAreLegacyCounterRotations:", (BOOL)(legacyRot));
            id cv = BP2B_Obj(c, sel_registerName("contentView"));
            if ([cv respondsToSelector:sel_registerName("setShouldStretchToBounds:")]) BP2B_S1(void, cv, "setShouldStretchToBounds:", (BOOL)(contentFill));
            if ([cv respondsToSelector:sel_registerName("setUsesNonuniformScaling:")]) BP2B_S1(void, cv, "setUsesNonuniformScaling:", (BOOL)(nonuniform));
            BOOL liveBlur = blurred && live != nil && blurTarget == 1;
            BP2B_S1(void, c, "setDraggable:", (BOOL)(draggable));
            BP2B_S1(void, c, "setSupportsSwitcherDragAndDrop:", (BOOL)(canDnD));
            Class blurEv = NSClassFromString(@"SBBlurProgressSwitcherModifierEvent");
            void (^began)(void) = ^{ id e = [blurEv alloc]; e = ((id (*)(id, SEL, double))objc_msgSend)(e, sel_registerName("initWithProgress:"), 0.0); BP2B_Obj1(vc, sel_registerName("_dispatchEventAndHandleAction:"), e); };
            void (^done)(void) = ^{ id e = [blurEv alloc]; e = ((id (*)(id, SEL, double))objc_msgSend)(e, sel_registerName("initWithProgress:"), 1.0); BP2B_Obj1(vc, sel_registerName("_dispatchEventAndHandleAction:"), e); };
            SEL liveBlurS = sel_registerName("setLiveContentBlurEnabled:duration:blurDelay:iconViewScale:began:completion:");
            if (live && [live respondsToSelector:liveBlurS])
                ((void (*)(id, SEL, BOOL, double, double, double, void (^)(void), void (^)(void)))objc_msgSend)(live, liveBlurS, liveBlur, 0.25, blurDelay, blurIcon, began, done);
            SEL blurS = sel_registerName("setBlurred:duration:blurDelay:iconViewScale:began:completion:");
            if ([c respondsToSelector:blurS])
                ((void (*)(id, SEL, BOOL, double, double, double, void (^)(void), void (^)(void)))objc_msgSend)(c, blurS, blurred && !liveBlur, 0.25, blurDelay, blurIcon, began, done);
            // 16.2 NEW: group opacity
            if ([root respondsToSelector:sel_registerName("shouldAllowGroupOpacityForAppLayout:")]) {
                BOOL gop = BP2B_Bool1(root, sel_registerName("shouldAllowGroupOpacityForAppLayout:"), appLayout);
                id layer = BP2B_Obj(c, @selector(layer));
                if ([layer respondsToSelector:@selector(setAllowsGroupOpacity:)]) [(CALayer *)layer setAllowsGroupOpacity:gop];
            }
            // ---- "center" ----
            BP2BDone mkCenter = make(@"center");
            BP2B_Animate(positionSettings, positionMode, ^{
                [(CALayer *)BP2B_Obj(c, @selector(layer)) setAnchorPoint:anchorApplied];
                BP2B_S1(void, c, "setCenter:", (CGPoint)(newC));
                BP2B_SetProp(repositionProp, 1.0);
            }, BP2B_CompletionFor(repositionProp, mkCenter));
            BP2B_S1(void, c, "setMaskedCorners:", (unsigned long long)(mc));
            // ---- "corner radius" ----
            BP2B_Animate(cornerSettings, cornerMode, ^{ BP2B_S1(void, c, "setContentCornerRadii:", (BP2BRadii)(rr)); }, (void (^)(BOOL, BOOL))make(@"corner radius"));
            // ---- "wallpaperGradientAttributes" (opacity settings) ----
            double gA = grad.b, gB = grad.a;
            if (leafs.count >= 2 && frame.size.width != 0) {
                gA = grad.b + gradDelta * CGRectGetMinX(R) / frame.size.width;
                gB = grad.b + gradDelta * CGRectGetMaxX(R) / frame.size.width;
            }
            BP2B_Animate(opacitySettings, opacityMode, ^{
                if ([c respondsToSelector:sel_registerName("setShouldUseWallpaperGradientTreatment:")]) BP2B_S1(void, c, "setShouldUseWallpaperGradientTreatment:", (BOOL)(wallpaperTreatment));
                struct { double a, b; } ga = { gA, gB };
                if ([c respondsToSelector:sel_registerName("setWallpaperGradientAttributes:")]) BP2B_S1(void, c, "setWallpaperGradientAttributes:", (__typeof__(ga))(ga));
            }, (void (^)(BOOL, BOOL))make(@"wallpaperGradientAttributes"));
            // ---- mesh transform (Jindo) ----
            SEL jindo = NULL; (void)jindo;
            {
                static BOOL (*enableJindo)(void); static dispatch_once_t oj;
                dispatch_once(&oj, ^{ enableJindo = (BOOL (*)(void))dlsym(RTLD_DEFAULT, "SBEnableJindo"); });
                CALayer *cl = BP2B_Obj(c, @selector(layer));
                if (enableJindo && enableJindo()) {
                    id curMesh = [cl valueForKey:@"meshTransform"];
                    BOOL needMesh = (curMesh == nil) && (mesh != nil);
                    BOOL inflight = BP2B_LayerHasModifier(cl, @[@"meshTransform"]);
                    id identity = (needMesh || inflight) ? BP2B_S1(id, root, "identityMeshTransformForIndex:", (NSUInteger)(idx)) : nil;
                    if (needMesh) [UIView performWithoutAnimation:^{ [cl setValue:identity forKey:@"meshTransform"]; }];
                    id animTarget = (!needMesh && mesh == nil && inflight) ? identity : mesh;
                    BP2B_Animate(meshSettings, meshMode, ^{ [cl setValue:animTarget forKey:@"meshTransform"]; }, (void (^)(BOOL, BOOL))make(@"mesh transform"));
                }
            }
            // ---- "bounds" ----
            void (^boundsBlock)(void) = ^{
                BP2BDone mk = make(@"bounds");
                BP2B_Animate(layoutSettings, layoutMode, ^{
                    BP2B_S1(void, c, "setBounds:", (CGRect)(BP2B_RectWithSize(R.size.width, R.size.height)));
                    BP2B_S1(void, c, "setPageViewAnchorPoint:", (CGPoint)(CGPointMake(pageAnchorX, 0.5)));
                    BP2B_S1(void, c, "setPageViewOffset:", (CGPoint)(pageOffset));
                    BP2B_S1(void, c, "setSizeForContainingSpace:", (CGSize)(frame.size));
                    BP2B_S1(void, c, "setMinimumTranslationForKillingContainer:", (double)(minKill));
                    BP2B_Obj(c, @selector(layoutIfNeeded));
                    BP2B_SetProp(resizeProp, 1.0);
                }, BP2B_CompletionFor(resizeProp, mk));
            };
            if (legacyRot) [UIView performWithoutAnimation:boundsBlock]; else boundsBlock();
            // ---- "clipping" (16.2: only when something changed) ----
            BOOL wasClipping = BP2B_Bool(c, sel_registerName("isContentClippingEnabled"));
            BOOL clipFrameChanged = wasClipping && !CGRectEqualToRect(BP2B_Rect(c, sel_registerName("contentClippingFrame")), clip);
            if ((clips != wasClipping) || clipFrameChanged) {
                BP2B_S1(void, c, "setContentClippingEnabled:", (BOOL)(clips));
                BP2BDone mkClip = make(@"clipping");
                BP2B_Animate(clippingSettings, clippingMode, ^{
                    BP2B_S2(void, c, "setContentClippingFrame:cornerRadii:", (CGRect)(clip), (BP2BRadii)(rr));
                    BP2B_Obj(c, @selector(layoutIfNeeded));
                }, ^(BOOL f, BOOL r) {
                    BP2B_S1(void, vc, "_noteItemContainerDidUpdateContentClippingWithMode:", (long long)(clippingMode));
                    if (mkClip) mkClip(f, r);
                });
            }
            // ---- "transform and content page view scale" ----
            BP2B_Animate(scaleSettings, scaleMode, ^{
                CALayer *l = BP2B_Obj(c, @selector(layer));
                [l setValue:@(layerScale) forKeyPath:@"transform.scale"];
                [l setValue:@(0.0) forKeyPath:@"transform.translation.x"];                         // compensation X (0 on this path)
                [l setValue:@(0.0) forKeyPath:@"transform.translation.y"];
                [l setValue:@(perspective) forKeyPath:@"transform.rotation.y"];
                [l setValue:@(rotation) forKeyPath:@"transform.rotation.z"];
                BP2B_S1(void, c, "setContentPageViewScale:", (double)(pageScale));
                BP2B_S1(void, c, "setBlurViewIconScale:", (double)(blurIcon));
                if (live) BP2B_S1(void, live, "setBlurViewIconScale:", (double)(blurIcon));
            }, (void (^)(BOOL, BOOL))make(@"transform and content page view scale"));
        }

        // ---- (3) accessories (162 0x1c7445248..0x1c7445a44) --------------------------------------------------------------------------
        __block BOOL anyRole = NO;
        BP2B_EnumerateValidRoles(^(long long r) {
            id item = ((id (*)(id, SEL, long long))objc_msgSend)(appLayout, sel_registerName("itemForLayoutRole:"), r);
            if (item && BP2B_RoleMaskContains(roleMask, r)) anyRole = YES;
        });
        __block unsigned long long allMask = 0;
        BP2B_EnumerateValidRoles(^(long long r) { allMask |= (1ull << r); });
        if (roleMask == allMask || anyRole) {                                                      // UNSURE: 162 compares with the constant at 0x1c7a933c8 (assumed "all valid roles")
            id overlay = overlayViews[appLayout], underlay = underlayViews[appLayout];
            double accScale = S;
            if ([root respondsToSelector:sel_registerName("adjustedSpaceAccessoryViewScale:forAppLayout:")]) {
                accScale = ((double (*)(id, SEL, double, id))objc_msgSend)(root, sel_registerName("adjustedSpaceAccessoryViewScale:forAppLayout:"), S, appLayout);
            }
            CGRect adjF = BP2B_S2(CGRect, root, "adjustedSpaceAccessoryViewFrame:forAppLayout:", (CGRect)(frame), (id)(appLayout));
            CGPoint adjA = BP2B_S2(CGPoint, root, "adjustedSpaceAccessoryViewAnchorPoint:forAppLayout:", (CGPoint)(anchor), (id)(appLayout));
            double accPageScale = pageScale;
            if (fabs(S) >= 1e-9) accPageScale = pageScale * (accScale / S);                    // 162 NEW: scale ratio (0x1c7445454..0x1c7445478)
            lastAdjScale = accScale; accessoriesRan = YES;
            BP2BDone m1 = make(@"accessory center");
            BP2B_Animate(positionSettings, positionMode, ^{
                for (id v in @[overlay ?: [NSNull null], underlay ?: [NSNull null]]) {
                    if (v == (id)[NSNull null]) continue;
                    [(CALayer *)BP2B_Obj(v, @selector(layer)) setAnchorPoint:adjA];
                    BP2B_S1(void, v, "setCenter:", (CGPoint)(CGPointMake(CGRectGetMidX(adjF), CGRectGetMidY(adjF))));
                }
            }, (void (^)(BOOL, BOOL))m1);
            for (id v in @[overlay ?: [NSNull null], underlay ?: [NSNull null]]) if (v != (id)[NSNull null]) BP2B_S1(void, v, "setMaskedCorners:", (unsigned long long)(maskedCorners));
            BP2B_Animate(cornerSettings, cornerMode, ^{
                for (id v in @[overlay ?: [NSNull null], underlay ?: [NSNull null]]) if (v != (id)[NSNull null]) BP2B_S1(void, v, "setCornerRadius:", (double)(minRadius));
            }, (void (^)(BOOL, BOOL))make(@"accessory corner radius"));
            BP2B_Animate(layoutSettings, layoutMode, ^{
                if (overlay) {
                    BP2B_S1(void, overlay, "setMultiWindowIndicatorRoleMask:", (unsigned long long)(multiMask));
                    BP2B_S1(void, overlay, "setBounds:", (CGRect)(BP2B_RectWithSize(adjF.size.width, adjF.size.height)));
                    BP2B_S1(void, overlay, "setContentViewOffset:", (CGPoint)(accOffset));
                    BP2B_Obj(overlay, @selector(layoutIfNeeded));
                }
                if (underlay) {
                    BP2B_S1(void, underlay, "setBounds:", (CGRect)(BP2B_RectWithSize(adjF.size.width, adjF.size.height)));
                    BP2B_S1(void, underlay, "setContentViewOffset:", (CGPoint)(accOffset));
                    BP2B_S1(void, underlay, "setResizeGrabberBounds:", (CGRect)(BP2B_RectWithSize(grabberRect.size.width, grabberRect.size.height)));
                    BP2B_S1(void, underlay, "setResizeGrabberCenter:", (CGPoint)(CGPointMake(CGRectGetMidX(grabberRect), CGRectGetMidY(grabberRect))));
                    BP2B_Obj(underlay, @selector(layoutIfNeeded));
                }
            }, (void (^)(BOOL, BOOL))make(@"accessory bounds"));
            for (id v in @[overlay ?: [NSNull null], underlay ?: [NSNull null]]) if (v != (id)[NSNull null]) BP2B_S1(void, v, "setContentClippingEnabled:", (BOOL)(clips));
            BP2B_Animate(clippingSettings, clippingMode, ^{
                for (id v in @[overlay ?: [NSNull null], underlay ?: [NSNull null]]) if (v != (id)[NSNull null]) {
                    BP2B_S2(void, v, "setContentClippingFrame:cornerRadii:", (CGRect)(clipIdx), (BP2BRadii)(radii));
                    BP2B_Obj(v, @selector(layoutIfNeeded));
                }
            }, (void (^)(BOOL, BOOL))make(@"accessory clipping"));
            BP2B_Animate(scaleSettings, scaleMode, ^{
                for (id v in @[overlay ?: [NSNull null], underlay ?: [NSNull null]]) {
                    if (v == (id)[NSNull null]) continue;
                    CALayer *l = BP2B_Obj(v, @selector(layer));
                    [l setValue:@(accScale) forKeyPath:@"transform.scale"];
                    [l setValue:@(rotation) forKeyPath:@"transform.rotation.z"];
                    if (v == overlay) {
                        BP2B_S1(void, v, "setIconAlignment:", (unsigned long long)((unsigned long long)(!perspectiveIsZero ? 0 : 1)));   // UNSURE polarity of [sp,#4]^1
                        BP2B_S1(void, v, "setUniqueIconsOnly:", (BOOL)(YES));
                        BP2B_S1(void, v, "setFooterStyle:", (unsigned long long)(BP2B_S0(unsigned long long, vc, "_itemContainerFooterStyle")));
                        id hg = BP2B_Obj(v, sel_registerName("homeGrabberView"));
                        if (hg) { BP2B_S1(void, hg, "setTransform3D:", (CATransform3D)(homeT)); BP2B_S1(void, hg, "setFrame:", (CGRect)(BP2B_RectWithSize(adjF.size.width, adjF.size.height))); }
                    }
                    BP2B_S1(void, v, "setContentScale:", (double)(accPageScale));
                    BP2B_Obj(v, @selector(layoutIfNeeded));
                }
            }, (void (^)(BOOL, BOOL))make(@"accessory transform and content page view scale"));
            static dispatch_once_t okb; static id kbSettings;
            dispatch_once(&okb, ^{                                                              // block_2: response 0.25, damping 1.0, frame rate range
                Class bs = NSClassFromString(@"SBFluidBehaviorSettings");
                kbSettings = [[bs alloc] initWithDefaultValues];
                if ([kbSettings respondsToSelector:@selector(setResponse:)]) ((void (*)(id, SEL, double))objc_msgSend)(kbSettings, @selector(setResponse:), 0.25);
                if ([kbSettings respondsToSelector:@selector(setDampingRatio:)]) ((void (*)(id, SEL, double))objc_msgSend)(kbSettings, @selector(setDampingRatio:), 1.0);
            });
            BP2B_Animate(kbSettings, 3, ^{
                for (id v in @[overlay ?: [NSNull null], underlay ?: [NSNull null]]) if (v != (id)[NSNull null])
                    BP2B_S1(void, v, "setKeyboardHeight:", (double)(BP2B_Dbl(vc, sel_registerName("keyboardHeight"))));
            }, (void (^)(BOOL, BOOL))make(@"accessory keyboard height"));
        }

        // ---- (4) item container backdrop (162 0x1c74459a4..0x1c7445a44) ----------------------------------------------------------------
        SEL bd = sel_registerName("_updateItemContainerBackdropPresenceForIndex:scale:rotation:cornerRadius:animationAttributes:completion:");
        if ([vc respondsToSelector:bd]) {
            BP2BDone mk = make(@"item container backdrop");
            ((void (*)(id, SEL, NSUInteger, double, double, double, id, id))objc_msgSend)(vc, bd, idx, accessoriesRan ? lastAdjScale : S, rotation, minRadius, attrsObj, mk);   // UNSURE: scale argument when no accessories
        }
        (void)lastR; (void)mesh; (void)ancX; (void)ancY; (void)clipIdx; (void)contentFill;
        #undef AM
        #undef MODE
        #undef ST
    };

    void (^performBlock)(BP2BMaker) = ^(BP2BMaker m) { body(m); };
    ((void (*)(Class, SEL, id, id, unsigned long long, id))objc_msgSend)(group, performS, performBlock, completion, 0ull, vc);
    #undef BP2B_FALLBACK
}

static void BP2B_SetupLayoutAppLayout(void) {
    Class vcc = objc_getClass("SBFluidSwitcherViewController");
    if (!vcc) return;
    SEL s = sel_registerName("_layoutAppLayout:roleMask:completion:");
    if (!class_getInstanceMethod(vcc, s)) { BP_Log(@"[g2b] item2: _layoutAppLayout:roleMask:completion: not found"); return; }
    // 16.2 selectors that the extended-protocol / ported modifiers expect on the VC are not needed here; only the method itself is replaced.
    gOrigLayoutAppLayout = BP2B_Replace(vcc, "_layoutAppLayout:roleMask:completion:", (IMP)BP2B_LayoutAppLayoutImpl);
    BP_Log(@"[g2b] item2: _layoutAppLayout:roleMask:completion: replaced");
}


// =================================================================================================================
// ITEM 5a-5g: keyboard navigation, shift-select, gesture-manager names, system aperture, per-display, pointer, strip tongue.
// New ivars of system classes (VC, item container, tap event) are held in associated objects (no alloc swizzling: the VC and the
// containers are created by SpringBoard, the tap events by the modifier code; an associated object works for every creator).
// =================================================================================================================

static BOOL BP2B_Chamois(id vc) { return BP2B_Bool(vc, sel_registerName("isChamoisWindowingUIEnabled")); }

// ---- 5b part 1: SBTapAppLayoutSwitcherModifierEvent gains modifierFlags + source (162 ivars +0x28 / +0x30) ----------------------------
static const void *kBP2B_TapFlags = &kBP2B_TapFlags, *kBP2B_TapSource = &kBP2B_TapSource;
static void BP2B_SetupTapEvent(void) {
    Class c = objc_getClass("SBTapAppLayoutSwitcherModifierEvent");
    if (!c) return;
    BP2B_AddIfMissing(c, "modifierFlags", imp_implementationWithBlock(^long long(id me) { return [objc_getAssociatedObject(me, kBP2B_TapFlags) longLongValue]; }), "q16@0:8");
    BP2B_AddIfMissing(c, "source", imp_implementationWithBlock(^long long(id me) { return [objc_getAssociatedObject(me, kBP2B_TapSource) longLongValue]; }), "q16@0:8");
    SEL init2 = sel_registerName("initWithAppLayout:layoutRole:");
    BP2B_AddIfMissing(c, "initWithAppLayout:layoutRole:modifierFlags:source:", imp_implementationWithBlock(^id(id me, id layout, long long role, long long flags, long long source) {
        id o = ((id (*)(id, SEL, id, long long))objc_msgSend)(me, init2, layout, role);
        if (o) { objc_setAssociatedObject(o, kBP2B_TapFlags, @(flags), OBJC_ASSOCIATION_RETAIN_NONATOMIC); objc_setAssociatedObject(o, kBP2B_TapSource, @(source), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
        return o;
    }), "@48@0:8@16q24q32q40");
    BP2B_AddIfMissing(c, "initWithAppLayout:layoutRole:modifierFlags:", imp_implementationWithBlock(^id(id me, id layout, long long role, long long flags) {
        id o = ((id (*)(id, SEL, id, long long))objc_msgSend)(me, init2, layout, role);
        if (o) objc_setAssociatedObject(o, kBP2B_TapFlags, @(flags), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return o;
    }), "@40@0:8@16q24q32");
    // events are copied by the modifier chain: carry the two values over
    SEL cz = @selector(copyWithZone:);
    static IMP origCopy;
    origCopy = BP2B_Replace(c, "copyWithZone:", imp_implementationWithBlock(^id(id me, void *zone) {
        id n = origCopy ? ((id (*)(id, SEL, void *))origCopy)(me, cz, zone) : me;
        if (n && n != me) {
            id f = objc_getAssociatedObject(me, kBP2B_TapFlags), s = objc_getAssociatedObject(me, kBP2B_TapSource);
            if (f) objc_setAssociatedObject(n, kBP2B_TapFlags, f, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            if (s) objc_setAssociatedObject(n, kBP2B_TapSource, s, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        return n;
    }));
}

// ---- 5b part 2: shift-select. VC -didSelectContainer:modifierFlags: (162 0x1c7452050) and the container callers --------------------------
static void BP2B_DispatchTap(id vc, id layout, long long role, long long flags, long long source, BOOL withSource) {
    Class te = NSClassFromString(@"SBTapAppLayoutSwitcherModifierEvent");
    id ev = [te alloc];
    SEL s4 = sel_registerName("initWithAppLayout:layoutRole:modifierFlags:source:"), s3 = sel_registerName("initWithAppLayout:layoutRole:modifierFlags:");
    if (withSource && [ev respondsToSelector:s4]) ev = ((id (*)(id, SEL, id, long long, long long, long long))objc_msgSend)(ev, s4, layout, role, flags, source);
    else if ([ev respondsToSelector:s3]) ev = ((id (*)(id, SEL, id, long long, long long))objc_msgSend)(ev, s3, layout, role, flags);
    else ev = ((id (*)(id, SEL, id, long long))objc_msgSend)(ev, sel_registerName("initWithAppLayout:layoutRole:"), layout, role);
    BP2B_Obj1(vc, sel_registerName("_dispatchEventAndHandleAction:"), ev);
}
static void BP2B_DidSelectContainer(id vc, id container, long long flags) {
    id leaf = BP2B_Obj(container, @selector(appLayout));
    if (!leaf) return;
    id item = ((id (*)(id, SEL, long long))objc_msgSend)(leaf, sel_registerName("itemForLayoutRole:"), 1);
    // per-scene locked pointer client: unlock the pointer for the window being selected (needs group4b's per-scene manager; guarded)
    id uid = BP2B_Obj(item, sel_registerName("uniqueIdentifier"));
    id lpm = BP2B_Obj(BP2B_Obj(vc, sel_registerName("_sbWindowScene")), sel_registerName("lockedPointerManager"));
    SEL clientS = sel_registerName("clientWithSceneIdentifier:suppressPreferredLockStatus:");
    if (uid && [lpm respondsToSelector:clientS]) (void)((id (*)(id, SEL, id, BOOL))objc_msgSend)(lpm, clientS, uid, NO);
    NSDictionary *adjustedMap = BP2B_IvarObj(vc, "_leafAppLayoutsToAdjustedAppLayouts");
    id adjusted = adjustedMap[leaf] ?: leaf;
    id root = BP2B_IvarObj(vc, "_rootModifier");
    BOOL shiftSelect = BP2B_Chamois(vc) && (flags & (1ll << 17)) && BP2B_Bool1(root, sel_registerName("canSelectLeafWithModifierKeysInAppLayout:"), adjusted);
    id layout = shiftSelect ? leaf : adjusted;
    long long role = ((long long (*)(id, SEL, id))objc_msgSend)(layout, sel_registerName("layoutRoleForItem:"), item);
    BP2B_DispatchTap(vc, layout, role, flags, 0, NO);
}
static void BP2B_SetupSelection(void) {
    Class vc = objc_getClass("SBFluidSwitcherViewController"), ic = objc_getClass("SBFluidSwitcherItemContainer");
    if (vc) BP2B_AddIfMissing(vc, "didSelectContainer:modifierFlags:", imp_implementationWithBlock(^(id me, id container, long long flags) { BP2B_DidSelectContainer(me, container, flags); }), "v32@0:8@16q24");
    if (!ic) return;
    SEL sc = sel_registerName("didSelectContainer:modifierFlags:");
    // 162 _handlePageViewTap: / _returnKeyPressed: forward [sender modifierFlags] (a gesture recognizer / UIKeyCommand)
    static IMP origTap, origRet;
    origTap = BP2B_Replace(ic, "_handlePageViewTap:", imp_implementationWithBlock(^(id me, id gr) {
        id d = BP2B_Obj(me, @selector(delegate));
        if (BP2B_Bool(me, sel_registerName("isSelectable")) && [d respondsToSelector:sc] && BP2B_Enabled("g2bkeys")) {
            long long flags = [gr respondsToSelector:@selector(modifierFlags)] ? ((long long (*)(id, SEL))objc_msgSend)(gr, @selector(modifierFlags)) : 0;
            ((void (*)(id, SEL, id, long long))objc_msgSend)(d, sc, me, flags);
        } else if (origTap) ((void (*)(id, SEL, id))origTap)(me, sel_registerName("_handlePageViewTap:"), gr);
    }));
    origRet = BP2B_Replace(ic, "_returnKeyPressed:", imp_implementationWithBlock(^(id me, id cmd) {
        id d = BP2B_Obj(me, @selector(delegate));
        if (BP2B_Bool(me, sel_registerName("isFocusable")) && BP2B_Bool(me, sel_registerName("isSelectable")) && [d respondsToSelector:sc] && BP2B_Enabled("g2bkeys")) {
            long long flags = [cmd respondsToSelector:@selector(modifierFlags)] ? ((long long (*)(id, SEL))objc_msgSend)(cmd, @selector(modifierFlags)) : 0;
            ((void (*)(id, SEL, id, long long))objc_msgSend)(d, sc, me, flags);
        } else if (origRet) ((void (*)(id, SEL, id))origRet)(me, sel_registerName("_returnKeyPressed:"), cmd);
    }));
}

// ---- 5a: keyboard window navigation (162 0x1c743b200 / 0x1c743b590 / 0x1c743b844) ------------------------------------------------------
// 162 _keyboardFocusableLiveAppLayoutsMatchingFocusedApp:foundAtIndex: (chamois branch): the list is the modifier's
// activeLeafAppLayoutsReachableByKeyboardShortcut compacted by: (matchFocusedApp -> same bundle id as the focused app), not part of a
// resigning set, and (when any active layout is a center window) environment in {2,3}.
static IMP gOrigKbdList, gOrigNavOld, gOrigCanPerform;
static NSArray *BP2B_KbdList(id vc, BOOL match, NSUInteger *outIdx) {
    id root = BP2B_IvarObj(vc, "_rootModifier");
    id coord = BP2B_IvarObj(vc, "_liveContentOverlayCoordinator");
    id focused = BP2B_Obj(coord, sel_registerName("appLayoutForKeyboardFocusedScene"));
    NSArray *active = BP2B_Obj(root, sel_registerName("activeLeafAppLayoutsReachableByKeyboardShortcut"));
    if (!active) return nil;
    id leaf0 = focused;
    if (!leaf0 && active.count) {
        id sc = BP2B_Obj(vc, sel_registerName("switcherController"));
        id cur = BP2B_Obj(BP2B_Obj(sc, sel_registerName("layoutState")), @selector(appLayout));
        leaf0 = [BP2B_Obj(cur, sel_registerName("zOrderedLeafAppLayouts")) firstObject];
    }
    NSString *focusedBundle = BP2B_Obj(BP2B_Obj([BP2B_Obj(leaf0, sel_registerName("allItems")) firstObject], @selector(self)), sel_registerName("bundleIdentifier"));
    BOOL anyCenter = NO;
    for (id l in active) if (BP2B_LL(l, sel_registerName("environment")) == 3) { anyCenter = YES; break; }
    NSMutableArray *out = [NSMutableArray array];
    for (id l in active) {
        if (match) {
            NSString *b = BP2B_Obj([BP2B_Obj(l, sel_registerName("allItems")) firstObject], sel_registerName("bundleIdentifier"));
            if (!focusedBundle || ![b isEqualToString:focusedBundle]) continue;
        }
        if (anyCenter && (BP2B_LL(l, sel_registerName("environment")) & ~1ll) != 2) continue;
        [out addObject:l];
    }
    if (outIdx) *outIdx = leaf0 ? [out indexOfObject:leaf0] : NSNotFound;
    return out;
}
static void BP2B_NavigateFromStrip(id vc, BOOL fwd, NSArray *reachable) {
    // 162 0x1c743b844: ring = the strip-reachable layouts with the current stage layout inserted at its group position; step +-1 with wrap.
    id sc = BP2B_Obj(vc, sel_registerName("switcherController"));
    id cur = BP2B_Obj(BP2B_Obj(sc, sel_registerName("layoutState")), @selector(appLayout));
    NSMutableArray *ring = [reachable mutableCopy] ?: [NSMutableArray array];
    NSString *curId = BP2B_Obj(cur, sel_registerName("continuousExposeIdentifier"));
    NSUInteger pos = ring.count;
    for (NSUInteger i = 0; i < ring.count; i++) {
        NSString *gid = BP2B_Obj(ring[i], sel_registerName("continuousExposeIdentifier"));
        if (curId && [gid isEqualToString:curId]) { pos = i; break; }
    }
    if (cur && ![ring containsObject:cur]) { [ring insertObject:cur atIndex:MIN(pos, ring.count)]; } else if (cur) { pos = [ring indexOfObject:cur]; }
    if (ring.count < 2) return;
    NSUInteger at = cur ? [ring indexOfObject:cur] : 0;
    NSUInteger next = fwd ? (at + 1) % ring.count : (at > 0 ? at - 1 : ring.count - 1);
    id target = ring[next];
    if (target == cur) return;
    NSDictionary *adjustedMap = BP2B_IvarObj(vc, "_leafAppLayoutsToAdjustedAppLayouts");
    id layout = adjustedMap[target] ?: target;
    id item = ((id (*)(id, SEL, long long))objc_msgSend)(target, sel_registerName("itemForLayoutRole:"), 1);
    long long role = ((long long (*)(id, SEL, id))objc_msgSend)(layout, sel_registerName("layoutRoleForItem:"), item);
    BP2B_DispatchTap(vc, layout, role, 0, 1, YES);
}
static void BP2B_NavigateKbd(id vc, BOOL fwd, BOOL match) {
    NSUInteger idx = NSNotFound;
    NSArray *list = BP2B_KbdList(vc, match, &idx);
    id root = BP2B_IvarObj(vc, "_rootModifier");
    NSArray *inactive = nil;
    if (match && idx != NSNotFound && idx < list.count) {
        NSString *fb = BP2B_Obj([BP2B_Obj(list[idx], sel_registerName("allItems")) firstObject], sel_registerName("bundleIdentifier"));
        NSArray *all = BP2B_Obj(root, sel_registerName("inactiveAppLayoutsReachableByKeyboardShortcut")) ?: @[];
        NSMutableArray *f = [NSMutableArray array];
        for (id l in all) { NSString *b = BP2B_Obj([BP2B_Obj(l, sel_registerName("allItems")) firstObject], sel_registerName("bundleIdentifier")); if ([b isEqualToString:fb]) [f addObject:l]; }
        inactive = f;
    } else if (!match) {
        inactive = BP2B_Obj(root, sel_registerName("inactiveAppLayoutsReachableByKeyboardShortcut"));
    }
    if (idx == NSNotFound) return;
    BOOL atEdge = fwd ? (idx == list.count - 1) : (idx == 0);
    if (atEdge && inactive.count) { BP2B_NavigateFromStrip(vc, fwd, inactive); return; }
    if (list.count < 2) return;
    NSUInteger next = fwd ? (idx + 1) % list.count : (idx > 0 ? idx - 1 : list.count - 1);
    id target = list[next];
    NSDictionary *adjustedMap = BP2B_IvarObj(vc, "_leafAppLayoutsToAdjustedAppLayouts");
    id layout = adjustedMap[target] ?: target;
    id item = ((id (*)(id, SEL, long long))objc_msgSend)(target, sel_registerName("itemForLayoutRole:"), 1);
    long long role = ((long long (*)(id, SEL, id))objc_msgSend)(layout, sel_registerName("layoutRoleForItem:"), item);
    BP2B_DispatchTap(vc, layout, role, 0, 1, YES);
}
static void BP2B_SetupKeyboardNav(void) {
    Class vc = objc_getClass("SBFluidSwitcherViewController");
    if (!vc) return;
    // 162 names (callable by ported code)
    BP2B_AddIfMissing(vc, "_navigateFromFocusedAppWindowSceneToNextSceneInForwardDirection:matchFocusedApp:", imp_implementationWithBlock(^(id me, BOOL fwd, BOOL match) { BP2B_NavigateKbd(me, fwd, match); }), "v24@0:8B16B20");
    BP2B_AddIfMissing(vc, "_navigateFromFocusedAppWindowSceneToNextSceneFromStripInForwardDirection:withReachableAppLayouts:", imp_implementationWithBlock(^(id me, BOOL fwd, NSArray *r) { BP2B_NavigateFromStrip(me, fwd, r); }), "v28@0:8B16@20");
    // 160 entry points: chamois -> 162 algorithm, otherwise the 16.0 code
    gOrigNavOld = BP2B_Replace(vc, "_navigateFromFocusedAppWindowSceneToNextScene:matchFocusedApp:", imp_implementationWithBlock(^(id me, BOOL fwd, BOOL match) {
        if (BP2B_Chamois(me) && BP2B_Enabled("g2bkeys")) { BP2B_NavigateKbd(me, fwd, match); return; }
        if (gOrigNavOld) ((void (*)(id, SEL, BOOL, BOOL))gOrigNavOld)(me, sel_registerName("_navigateFromFocusedAppWindowSceneToNextScene:matchFocusedApp:"), fwd, match);
    }));
    gOrigKbdList = BP2B_Replace(vc, "_keyboardFocusableLiveAppLayoutsMatchingFocusedApp:foundAtIndex:", imp_implementationWithBlock(^id(id me, BOOL match, NSUInteger *outIdx) {
        if (BP2B_Chamois(me) && BP2B_Enabled("g2bkeys")) { NSArray *l = BP2B_KbdList(me, match, outIdx); if (l) return l; }
        return gOrigKbdList ? ((id (*)(id, SEL, BOOL, NSUInteger *))gOrigKbdList)(me, sel_registerName("_keyboardFocusableLiveAppLayoutsMatchingFocusedApp:foundAtIndex:"), match, outIdx) : nil;
    }));
    // can-perform: window navigation actions (4,5 same-app next/previous window, 15,16 next/previous window) are available whenever the modifier
    // exposes at least one reachable layout other than the focused one (UNSURE: 162's version is a 280 insn decision tree)
    gOrigCanPerform = BP2B_Replace(vc, "canPerformKeyboardShortcutAction:forBundleIdentifier:", imp_implementationWithBlock(^BOOL(id me, long long action, id bid) {
        BOOL r = gOrigCanPerform ? ((BOOL (*)(id, SEL, long long, id))gOrigCanPerform)(me, sel_registerName("canPerformKeyboardShortcutAction:forBundleIdentifier:"), action, bid) : NO;
        if (r || !BP2B_Chamois(me) || !BP2B_Enabled("g2bkeys")) return r;
        if (action == 4 || action == 5 || action == 15 || action == 16) {
            id root = BP2B_IvarObj(me, "_rootModifier");
            return [BP2B_Obj(root, sel_registerName("activeLeafAppLayoutsReachableByKeyboardShortcut")) count] + [BP2B_Obj(root, sel_registerName("inactiveAppLayoutsReachableByKeyboardShortcut")) count] > 1;
        }
        return r;
    }));
}

// ---- 5c: gesture-manager API names (162: handleFluidSwitcherGestureManager:didBegin/Update/EndGesture:) ------------------------------------
// 16.0 manager/controller call handleGestureDidBegin:/Update:/End: ; 162 bodies are identical to the 160 ones plus an assertion that the manager is the
// switcher controller's gestureManager (or the event is a cross-display CE window drag). The 162 names are added as forwarders so ported callers work.
static id BP2B_ConvertCEDragEvent(id vc, id event, id fromContentVC) {
    // 162 0x1c745f3b0: re-express a window-drag event that came from the NEIGHBOURING display's switcher in this display's coordinates
    UIViewController *other = [fromContentVC isKindOfClass:[UIViewController class]] ? fromContentVC : nil;
    if (!other || other == vc) return event;
    id myScene = BP2B_Obj(vc, sel_registerName("_sbWindowScene")), otherScene = BP2B_Obj(other, sel_registerName("_sbWindowScene"));
    SEL cp = sel_registerName("convertPoint:toNeighboringDisplayWindowScene:");
    SEL ca = sel_registerName("convertAppLayout:fromSwitcherController:toSwitcherController:");
    if (![otherScene respondsToSelector:cp]) return event;
    CGPoint loc = ((CGPoint (*)(id, SEL, CGPoint, id))objc_msgSend)(otherScene, cp, BP2B_Point(event, sel_registerName("locationInContainerView")), myScene);
    id fromSC = BP2B_Obj(otherScene, sel_registerName("switcherController")), toSC = BP2B_Obj(myScene, sel_registerName("switcherController"));
    id coord = BP2B_Obj(fromSC, sel_registerName("switcherCoordinator"));
    id al = BP2B_Obj(event, sel_registerName("selectedAppLayout"));
    if ([coord respondsToSelector:ca]) al = ((id (*)(id, SEL, id, id, id))objc_msgSend)(coord, ca, al, fromSC, toSC) ?: al;
    Class ec = [event class];
    id n = [ec alloc];
    SEL ini = sel_registerName("initWithGestureID:selectedAppLayout:gestureType:phase:");
    if (![n respondsToSelector:ini]) return event;
    n = ((id (*)(id, SEL, long long, id, long long, long long))objc_msgSend)(n, ini, BP2B_LL(event, sel_registerName("gestureID")), al, BP2B_LL(event, sel_registerName("gestureType")), BP2B_LL(event, sel_registerName("phase")));
    ((void (*)(id, SEL, CGPoint))objc_msgSend)(n, sel_registerName("setLocationInContainerView:"), loc);
    if ([n respondsToSelector:sel_registerName("setDraggingFromContinuousExposeStrips:")]) ((void (*)(id, SEL, BOOL))objc_msgSend)(n, sel_registerName("setDraggingFromContinuousExposeStrips:"), BP2B_Bool(event, sel_registerName("isDraggingFromContinuousExposeStrips")));
    if ([n respondsToSelector:sel_registerName("setLocationInSelectedDisplayItem:")]) ((void (*)(id, SEL, CGPoint))objc_msgSend)(n, sel_registerName("setLocationInSelectedDisplayItem:"), BP2B_Point(event, sel_registerName("locationInSelectedDisplayItem")));
    if ([n respondsToSelector:sel_registerName("setSizeOfSelectedDisplayItem:")]) ((void (*)(id, SEL, CGSize))objc_msgSend)(n, sel_registerName("setSizeOfSelectedDisplayItem:"), BP2B_Size(event, sel_registerName("sizeOfSelectedDisplayItem")));
    return n;
}
static void BP2B_SetupGestureNames(void) {
    Class vc = objc_getClass("SBFluidSwitcherViewController");
    if (!vc) return;
    struct { const char *n, *old; } t[] = { { "handleFluidSwitcherGestureManager:didBeginGesture:", "handleGestureDidBegin:" }, { "handleFluidSwitcherGestureManager:didUpdateGesture:", "handleGestureDidUpdate:" }, { "handleFluidSwitcherGestureManager:didEndGesture:", "handleGestureDidEnd:" } };
    for (size_t i = 0; i < 3; i++) {
        SEL old = sel_registerName(t[i].old);
        BP2B_AddIfMissing(vc, t[i].n, imp_implementationWithBlock(^(id me, id manager, id gesture) {
            if ([me respondsToSelector:old]) ((void (*)(id, SEL, id))objc_msgSend)(me, old, gesture);
        }), "v32@0:8@16@24");
    }
    BP2B_AddIfMissing(vc, "_convertContinuousExposeWindowDragEvent:fromSwitcherContentViewController:", imp_implementationWithBlock(^id(id me, id ev, id from) { return BP2B_ConvertCEDragEvent(me, ev, from); }), "@32@0:8@16@24");
    BP2B_AddIfMissing(vc, "_adjustedGestureEventForGestureEvent:fromGestureManager:", imp_implementationWithBlock(^id(id me, id ev, id mgr) {
        if (BP2B_Bool(ev, sel_registerName("isContinuousExposeWindowDragEvent"))) {
            id other = BP2B_Obj(BP2B_Obj(me, sel_registerName("switcherController")), sel_registerName("contentViewController"));
            return BP2B_ConvertCEDragEvent(me, ev, other);
        }
        return ev;
    }), "@32@0:8@16@24");
}

// ---- 5d: system aperture suppression responses (162 0x1c745e4f4 / 0x1c745e788 / 0x1c745e8e8) -------------------------------------------------
static const void *kBP2B_GlobalAsserts = &kBP2B_GlobalAsserts;
static NSMutableDictionary *BP2B_GlobalAsserts(id vc) {
    NSMutableDictionary *d = objc_getAssociatedObject(vc, kBP2B_GlobalAsserts);
    if (!d) { d = [NSMutableDictionary dictionary]; objc_setAssociatedObject(vc, kBP2B_GlobalAsserts, d, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    return d;
}
static id BP2B_ApertureController(void) {
    // 162 sends systemApertureControllerForMainDisplay to a singleton (class ref 0x1dd7eeeb0); look for the singleton that answers it.
    SEL s = sel_registerName("systemApertureControllerForMainDisplay");
    for (NSString *n in @[@"SBSystemApertureController", @"SBSceneManagerCoordinator", @"SBSystemApertureManager", @"SBApertureController"]) {
        Class k = NSClassFromString(n);
        id inst = k ? BP2B_Obj((id)k, sel_registerName("sharedInstance")) : nil;
        if (inst && [inst respondsToSelector:s]) return BP2B_Obj(inst, s);
    }
    return nil;
}
static void BP2B_SetupAperture(void) {
    Class vc = objc_getClass("SBFluidSwitcherViewController");
    if (!vc) return;
    static IMP oReq, oRel, oBounce;
    SEL rs = sel_registerName("_performRequestSystemApertureElementSuppressionResponse:");
    oReq = BP2B_Replace(vc, "_performRequestSystemApertureElementSuppressionResponse:", imp_implementationWithBlock(^(id me, id resp) {
        if (oReq) ((void (*)(id, SEL, id))oReq)(me, rs, resp);
        if (!BP2B_Enabled("g2baperture")) return;
        if (!BP2B_Bool(resp, sel_registerName("wantsGlobalSuppression"))) return;
        id settings = BP2B_Obj(BP2B_IvarObj(me, "_settings"), sel_registerName("systemApertureSettings"));
        if (settings && ![settings respondsToSelector:sel_registerName("zoomToJindoCollapseToInert")]) return;            // 16.0 settings have no such flag: nothing to do
        if (settings && !BP2B_Bool(settings, sel_registerName("zoomToJindoCollapseToInert"))) return;
        id ctrl = BP2B_ApertureController();
        SEL rr = sel_registerName("restrictSystemApertureToInertWithReason:");
        if (!ctrl || ![ctrl respondsToSelector:rr]) return;
        id assertion = BP2B_Obj1(ctrl, rr, @"Switcher");
        id key = BP2B_Obj(resp, sel_registerName("invalidationIdentifier"));
        if (assertion && key) BP2B_GlobalAsserts(me)[key] = assertion;
    }));
    SEL rls = sel_registerName("_performRelinquishSystemApertureElementSuppressionResponse:");
    oRel = BP2B_Replace(vc, "_performRelinquishSystemApertureElementSuppressionResponse:", imp_implementationWithBlock(^(id me, id resp) {
        if (oRel) ((void (*)(id, SEL, id))oRel)(me, rls, resp);
        id key = BP2B_Obj(resp, sel_registerName("invalidationIdentifier"));
        id a = key ? BP2B_GlobalAsserts(me)[key] : nil;
        if (a) { SEL inv = sel_registerName("invalidateWithReason:"); if ([a respondsToSelector:inv]) ((void (*)(id, SEL, id))objc_msgSend)(a, inv, @"Switcher"); [BP2B_GlobalAsserts(me) removeObjectForKey:key]; }
    }));
    SEL bs = sel_registerName("_performSystemApertureBounceResponse:");
    oBounce = BP2B_Replace(vc, "_performSystemApertureBounceResponse:", imp_implementationWithBlock(^(id me, id resp) {
        if (oBounce) ((void (*)(id, SEL, id))oBounce)(me, bs, resp);
        id key = BP2B_Obj(resp, sel_registerName("suppressionIdentifierToInvalidate"));
        id a = key ? BP2B_GlobalAsserts(me)[key] : nil;
        if (a) { SEL inv = sel_registerName("invalidateWithReason:"); if ([a respondsToSelector:inv]) ((void (*)(id, SEL, id))objc_msgSend)(a, inv, @"Switcher"); [BP2B_GlobalAsserts(me) removeObjectForKey:key]; }
    }));
}

// ---- 5e: per-display: home-grabber click suspends only the ACTIVE display (162 0x1c743a460) ----------------------------------------------------
// 160 calls _SBWorkspaceSuspendAllDisplays at the end of the click; 162 calls _SBWorkspaceSuspendActiveDisplay (0x1c736e970 = a thin entry into
// __SBWorkspaceActivateSpringBoardWithResult(nil, nil, animated=1, 1, 0, nil, nil), 160's entry has the arguments (nil, allDisplays=1, 1, 0, nil, nil)).
// UNSURE: 16.0 has no single-display entry. The port: when more than one display window scene is connected the click is routed to the main
// workspace for the display of the grabber's window scene (a transition request with that display configuration); with one display the 16.0 call stays.
static void BP2B_SetupGrabberClick(void) {
    // Decision (md 5.6): the 16.0 body is kept. The only 16.2 difference is the last call (_SBWorkspaceSuspendActiveDisplay instead of
    // _SBWorkspaceSuspendAllDisplays); 16.0 has no single-display entry into __SBWorkspaceActivateSpringBoardWithResult and replacing it with a
    // guessed transition request would break the click. If the process exports SBWorkspaceSuspendActiveDisplay (a 16.2-like runtime) nothing is
    // needed either. Nothing is installed.
}

// ---- 5f: pointer edge-resize in the item container (162 0x1c75e44a8 / 0x1c75e4570 / 0x1c75e4858 / 0x1c75e48f8 / init 0x1c75e10b4) --------------
static const void *kBP2B_CScene = &kBP2B_CScene, *kBP2B_CSuppressed = &kBP2B_CSuppressed;
static void BP2B_SetupContainerPointer(void) {
    Class ic = objc_getClass("SBFluidSwitcherItemContainer");
    if (!ic) return;
    SEL old = sel_registerName("pointerIsHoveringOverEdge:");
    // 162 renames: -[container appSwitcherPageView:pointerIsHoveringOverEdge:] (the page view is now passed) and -_updateForPointerHoveringOverEdge:
    BP2B_AddIfMissing(ic, "_updateForPointerHoveringOverEdge:", imp_implementationWithBlock(^(id me, BOOL hover) { if ([me respondsToSelector:old]) ((void (*)(id, SEL, BOOL))objc_msgSend)(me, old, hover); }), "v20@0:8B16");
    BP2B_AddIfMissing(ic, "appSwitcherPageView:pointerIsHoveringOverEdge:", imp_implementationWithBlock(^(id me, id pv, BOOL hover) { if ([me respondsToSelector:old]) ((void (*)(id, SEL, BOOL))objc_msgSend)(me, old, hover); }), "v28@0:8@16B24");
    // preferred pointer lock status suppression (new ivar -> associated object); reset by prepareForReuse
    BP2B_AddIfMissing(ic, "isPreferredPointerLockStatusSuppressed", imp_implementationWithBlock(^BOOL(id me) { return [objc_getAssociatedObject(me, kBP2B_CSuppressed) boolValue]; }), "B16@0:8");
    BP2B_AddIfMissing(ic, "setPreferredPointerLockStatusSuppressed:", imp_implementationWithBlock(^(id me, BOOL v) { objc_setAssociatedObject(me, kBP2B_CSuppressed, @(v), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }), "v20@0:8B16");
    static IMP oReuse;
    oReuse = BP2B_Replace(ic, "prepareForReuse", imp_implementationWithBlock(^(id me) {
        if (oReuse) ((void (*)(id, SEL))oReuse)(me, @selector(prepareForReuse));
        objc_setAssociatedObject(me, kBP2B_CSuppressed, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }));
    // windowScene argument of the 162 initialiser
    BP2B_AddIfMissing(ic, "initWithFrame:appLayout:delegate:active:windowScene:", imp_implementationWithBlock(^id(id me, CGRect f, id layout, id delegate, BOOL active, id scene) {
        SEL i4 = sel_registerName("initWithFrame:appLayout:delegate:active:");
        id o = ((id (*)(id, SEL, CGRect, id, id, BOOL))objc_msgSend)(me, i4, f, layout, delegate, active);
        if (o && scene) objc_setAssociatedObject(o, kBP2B_CScene, scene, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return o;
    }), "@64@0:8{CGRect={CGPoint=dd}{CGSize=dd}}16@48@56B64@72");
    BP2B_AddIfMissing(ic, "windowScene", imp_implementationWithBlock(^id(id me) {
        id s = objc_getAssociatedObject(me, kBP2B_CScene);
        return s ?: BP2B_Obj(BP2B_Obj(me, @selector(delegate)), sel_registerName("_sbWindowScene"));            // 16.0 containers: the delegate is the VC of that scene
    }), "@16@0:8");
}

// ---- 5g: Continuous Expose strip tongue (162 SBContinuousExposeStripTongueView 0x1c797196c.. ; VC hosting 0x1c7459648 / 0x1c744306c) -------------------
typedef struct { unsigned long long state, direction; } BP2BTongueAttrs;      // SBSwitcherContinuousExposeStripTongueAttributes (state 0 none, 1 hidden, 2 shown)
@protocol SBContinuousExposeStripTongueViewDelegate <NSObject>
- (void)continuousExposeStripTongueView:(id)view didFinishAnimatingToState:(unsigned long long)state;
- (void)continuousExposeStripTongueViewTapped:(id)view;
@end
@interface SBContinuousExposeStripTongueView : UIView
@property (nonatomic, weak) id<SBContinuousExposeStripTongueViewDelegate> delegate;
@property (nonatomic, readonly) BP2BTongueAttrs attributes;
@property (nonatomic, readonly, getter=isAnimating) BOOL animating;
- (void)setAttributes:(BP2BTongueAttrs)attributes animated:(BOOL)animated;
@end
@implementation SBContinuousExposeStripTongueView {
    UIView *_tongueContainerView; UIImageView *_chevronImageView; UIImageView *_tongueMaskView; UIView *_backdropView;
    UITapGestureRecognizer *_tap; CGSize _bitmapMaskSize; BOOL _animating; BP2BTongueAttrs _attributes;
}
@synthesize delegate = _delegate;
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _attributes.state = 0; _attributes.direction = 0;                                          // _SBSwitcherContinuousExposeStripTongueAttributesNone
    UIImage *mask = [UIImage imageNamed:@"SlideOverTongueMask"];                                // the Slide Over tongue bitmap, shared with 16.0
    _bitmapMaskSize = mask.size;
    _tongueContainerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, _bitmapMaskSize.width, _bitmapMaskSize.height)];
    _tongueContainerView.layer.anchorPoint = CGPointMake(1.0, 0.5);
    [self addSubview:_tongueContainerView];
    Class bd = NSClassFromString(@"_UIBackdropView");
    _backdropView = bd ? ((id (*)(id, SEL, long long))objc_msgSend)([bd alloc], sel_registerName("initWithPrivateStyle:"), -2) : [UIView new];
    id inputs = BP2B_Obj(_backdropView, sel_registerName("inputSettings"));
    if ([inputs respondsToSelector:@selector(setBlurRadius:)]) ((void (*)(id, SEL, double))objc_msgSend)(inputs, @selector(setBlurRadius:), 0.0);
    if ([inputs respondsToSelector:@selector(setScale:)]) ((void (*)(id, SEL, double))objc_msgSend)(inputs, @selector(setScale:), 1.0);
    if ([inputs respondsToSelector:@selector(setBackdropVisible:)]) ((void (*)(id, SEL, BOOL))objc_msgSend)(inputs, @selector(setBackdropVisible:), YES);
    [_tongueContainerView addSubview:_backdropView];
    _tongueMaskView = [[UIImageView alloc] initWithImage:mask];
    _tongueMaskView.contentMode = UIViewContentModeScaleToFill;
    _tongueMaskView.layer.compositingFilter = @"destOut";                                       // UNSURE: 162 loads a CA compositing filter constant (0x1d83ef000+0xa90)
    [_tongueContainerView addSubview:_tongueMaskView];
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:34.0];        // 0x4046... == 44? decoded as the double constant; UNSURE value
    _chevronImageView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.compact.left" withConfiguration:cfg]];
    _chevronImageView.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;
    _chevronImageView.tintColor = [UIColor blackColor];
    [_tongueContainerView addSubview:_chevronImageView];
    _tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_handleTap:)];
    [_tongueContainerView addGestureRecognizer:_tap];
    self.isAccessibilityElement = YES;
    self.accessibilityIdentifier = @"continuous-expose-strip-tongue";
    return self;
}
- (BP2BTongueAttrs)attributes { return _attributes; }
- (BOOL)isAnimating { return _animating; }
- (void)_updateContainerPosition { _tongueContainerView.center = CGPointMake(_attributes.direction == 1 ? 0.0 : self.bounds.size.width, self.bounds.size.height * 0.5); }
- (void)_updateContainerTransform { _tongueContainerView.transform = (_attributes.direction == 2) ? CGAffineTransformMakeScale(-1.0, 1.0) : CGAffineTransformIdentity; }
- (void)_updateSubviewLayoutForCollapsedOrExpandedState {
    CGAffineTransform t = (_attributes.state == 1) ? CGAffineTransformMakeScale(0.0, 1.0) : CGAffineTransformIdentity;
    _backdropView.transform = t; _tongueMaskView.transform = t; _chevronImageView.transform = t;
    CGFloat cx = (_attributes.state == 1) ? _bitmapMaskSize.width : _bitmapMaskSize.width * 0.5, cy = floor(_bitmapMaskSize.height * 0.5);
    _backdropView.center = CGPointMake(cx, cy); _tongueMaskView.center = CGPointMake(cx, cy); _chevronImageView.center = CGPointMake(cx, cy);
}
- (void)_updateSubviewOpacityForCollapsedOrExpandedState { _chevronImageView.alpha = (_attributes.state == 2) ? 1.0 : 0.0; }
- (void)layoutSubviews { [super layoutSubviews]; [self _updateContainerPosition]; [self _updateContainerTransform]; [self _updateSubviewLayoutForCollapsedOrExpandedState]; }
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event { return [_tongueContainerView pointInside:[self convertPoint:point toView:_tongueContainerView] withEvent:event]; }
- (void)_handleTap:(id)tap { [_delegate continuousExposeStripTongueViewTapped:self]; }
- (void)setAttributes:(BP2BTongueAttrs)attributes animated:(BOOL)animated {
    BP2BTongueAttrs old = _attributes;
    _attributes = attributes;
    [self _updateContainerPosition]; [self _updateContainerTransform];
    if (old.state == attributes.state || !animated) {
        [self _updateSubviewLayoutForCollapsedOrExpandedState]; [self _updateSubviewOpacityForCollapsedOrExpandedState];
        return;
    }
    id root = BP2B_Obj((id)NSClassFromString(@"SBAppSwitcherDomain"), sel_registerName("rootSettings"));
    id fs = BP2B_Obj(root, sel_registerName("floatingSwitcherSettings"));
    id settings = BP2B_Obj(fs, old.state == 1 ? sel_registerName("tongueCollapsedToExpandedAnimationSettings") : sel_registerName("tongueExpandedToCollapsedAnimationSettings"));
    _animating = YES;
    __weak SBContinuousExposeStripTongueView *wself = self;
    unsigned long long target = attributes.state;
    BP2B_Animate(settings, 3, ^{ [wself _updateSubviewLayoutForCollapsedOrExpandedState]; [wself _updateSubviewOpacityForCollapsedOrExpandedState]; },
                 ^(BOOL f, BOOL r) { SBContinuousExposeStripTongueView *s = wself; if (!s) return; s->_animating = NO; [s->_delegate continuousExposeStripTongueView:s didFinishAnimatingToState:target]; });
}
@end

static const void *kBP2B_Tongue = &kBP2B_Tongue, *kBP2B_TongueBackdrop = &kBP2B_TongueBackdrop, *kBP2B_TongueElement = &kBP2B_TongueElement, *kBP2B_StripOpts = &kBP2B_StripOpts;
static BP2BTongueAttrs BP2B_TongueAttrsFor(id vc) {
    id root = BP2B_IvarObj(vc, "_rootModifier");
    SEL s = sel_registerName("continuousExposeStripTongueAttributes");
    BP2BTongueAttrs z = { 0, 0 };
    return (root && [root respondsToSelector:s]) ? ((BP2BTongueAttrs (*)(id, SEL))objc_msgSend)(root, s) : z;
}
static void BP2B_LayoutTongue(id vc, BOOL animated, void (^completion)(void)) {
    SBContinuousExposeStripTongueView *t = objc_getAssociatedObject(vc, kBP2B_Tongue);
    if (t) {
        BP2BTongueAttrs a = BP2B_TongueAttrsFor(vc);
        CGRect b = BP2B_Rect(vc, sel_registerName("containerViewBounds"));
        t.bounds = b; t.center = CGPointMake(CGRectGetMidX(b), CGRectGetMidY(b));
        UIView *bd = objc_getAssociatedObject(vc, kBP2B_TongueBackdrop);
        bd.bounds = b; bd.center = CGPointMake(CGRectGetMidX(b), CGRectGetMidY(b));
        [t setAttributes:a animated:animated];
    }
    if (completion) completion();
}
static void BP2B_UpdateTonguePresence(id vc) {
    BP2BTongueAttrs a = BP2B_TongueAttrsFor(vc);
    SBContinuousExposeStripTongueView *t = objc_getAssociatedObject(vc, kBP2B_Tongue);
    UIView *content = BP2B_IvarObj(vc, "_contentView");
    if (a.state == 2 && content) {
        if (!t) {
            t = [SBContinuousExposeStripTongueView new];
            t.delegate = (id)vc;
            objc_setAssociatedObject(vc, kBP2B_Tongue, t, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [content addSubview:t];
            Class bdc = NSClassFromString(@"_UIBackdropView");
            id bd = bdc ? ((id (*)(id, SEL, long long))objc_msgSend)([bdc alloc], sel_registerName("initWithPrivateStyle:"), -2) : nil;
            id in = BP2B_Obj(bd, sel_registerName("inputSettings"));
            if ([in respondsToSelector:@selector(setBlurRadius:)]) ((void (*)(id, SEL, double))objc_msgSend)(in, @selector(setBlurRadius:), 0.0);
            if ([in respondsToSelector:@selector(setScale:)]) ((void (*)(id, SEL, double))objc_msgSend)(in, @selector(setScale:), 1.0);
            if ([in respondsToSelector:@selector(setBackdropVisible:)]) ((void (*)(id, SEL, BOOL))objc_msgSend)(in, @selector(setBackdropVisible:), YES);
            id eff = BP2B_Obj(bd, sel_registerName("effectView"));
            CALayer *l = BP2B_Obj(eff, @selector(layer));
            if ([l respondsToSelector:sel_registerName("setCaptureOnly:")]) ((void (*)(id, SEL, BOOL))objc_msgSend)(l, sel_registerName("setCaptureOnly:"), NO);     // UNSURE: layer class cast is SBSafeCast(0x...2b0)
            if (bd) { [content addSubview:bd]; objc_setAssociatedObject(vc, kBP2B_TongueBackdrop, bd, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
            Class le = NSClassFromString(@"SBSwitcherLayoutElement");                                                                // class at 0x1db40b9f0; type 6 = tongue backdrop capture element
            id el = le ? ((id (*)(id, SEL, long long))objc_msgSend)([le alloc], sel_registerName("initWithType:"), 6) : nil;
            if (el) objc_setAssociatedObject(vc, kBP2B_TongueElement, el, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            BP2B_Obj(vc, sel_registerName("_ensureSubviewOrdering"));
            BP2B_LayoutTongue(vc, NO, nil);
            BP2BTongueAttrs hidden = { 1, a.direction };
            [t setAttributes:hidden animated:NO];
        }
        [t setAttributes:a animated:YES];
    } else if (t && !t.isAnimating) {
        [t removeFromSuperview];
        objc_setAssociatedObject(vc, kBP2B_Tongue, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [(UIView *)objc_getAssociatedObject(vc, kBP2B_TongueBackdrop) removeFromSuperview];
        objc_setAssociatedObject(vc, kBP2B_TongueBackdrop, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(vc, kBP2B_TongueElement, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        BP2B_Obj(vc, sel_registerName("_ensureSubviewOrdering"));
    }
}
static void BP2B_SetupTongue(void) {
    Class vc = objc_getClass("SBFluidSwitcherViewController");
    if (!vc) return;
    BP2B_AddIfMissing(vc, "_updateContinuousExposeStripTonguePresence", imp_implementationWithBlock(^(id me) { BP2B_UpdateTonguePresence(me); }), "v16@0:8");
    BP2B_AddIfMissing(vc, "_layoutContinuousExposeStripTongueAnimated:completion:", imp_implementationWithBlock(^(id me, BOOL animated, void (^completion)(void)) { BP2B_LayoutTongue(me, animated, completion); }), "v32@0:8B16@?24");
    BP2B_AddIfMissing(vc, "continuousExposeStripTongueView:didFinishAnimatingToState:", imp_implementationWithBlock(^(id me, id view, unsigned long long state) { BP2B_UpdateTonguePresence(me); }), "v32@0:8@16Q24");
    BP2B_AddIfMissing(vc, "continuousExposeStripTongueViewTapped:", imp_implementationWithBlock(^(id me, id view) {
        unsigned long long o = [objc_getAssociatedObject(me, kBP2B_StripOpts) unsignedLongLongValue];
        if (!(o & 1)) {
            objc_setAssociatedObject(me, kBP2B_StripOpts, @(o | 1), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            Class rc = NSClassFromString(@"SBUpdateLayoutSwitcherEventResponse");
            id r = rc ? ((id (*)(id, SEL, unsigned long long, long long))objc_msgSend)([rc alloc], sel_registerName("initWithOptions:updateMode:"), 0x1eull, 3ll) : nil;
            if (r) BP2B_Obj1(me, sel_registerName("_handleEventResponse:"), r);
        }
        if ([me respondsToSelector:sel_registerName("dismissContinuousExposeStripEdgeProtectTongue")]) BP2B_Obj(me, sel_registerName("dismissContinuousExposeStripEdgeProtectTongue"));
        BP2B_UpdateTonguePresence(me);
    }), "v24@0:8@16");
    // post-event / post-layout / ordering hooks (162 calls these from _updateImplicitModifierStackInvalidatables / _updateLayoutWithCompletion: / _ensureSubviewOrdering)
    static IMP oDisp, oLayout, oOrder;
    oDisp = BP2B_Replace(vc, "_dispatchEventAndHandleAction:", imp_implementationWithBlock(^id(id me, id ev) {
        id r = oDisp ? ((id (*)(id, SEL, id))oDisp)(me, sel_registerName("_dispatchEventAndHandleAction:"), ev) : nil;
        if (BP2B_Enabled("g2btongue") && BP2B_Chamois(me)) BP2B_UpdateTonguePresence(me);
        return r;
    }));
    oLayout = BP2B_Replace(vc, "_updateLayoutWithCompletion:", imp_implementationWithBlock(^(id me, id completion) {
        if (oLayout) ((void (*)(id, SEL, id))oLayout)(me, sel_registerName("_updateLayoutWithCompletion:"), completion);
        if (BP2B_Enabled("g2btongue") && objc_getAssociatedObject(me, kBP2B_Tongue)) BP2B_LayoutTongue(me, NO, nil);
    }));
    oOrder = BP2B_Replace(vc, "_ensureSubviewOrdering", imp_implementationWithBlock(^(id me) {
        if (oOrder) ((void (*)(id, SEL))oOrder)(me, sel_registerName("_ensureSubviewOrdering"));
        UIView *content = BP2B_IvarObj(me, "_contentView");
        UIView *bd = objc_getAssociatedObject(me, kBP2B_TongueBackdrop), *t = objc_getAssociatedObject(me, kBP2B_Tongue);
        if (bd.superview == content) [content bringSubviewToFront:bd];
        if (t.superview == content) [content bringSubviewToFront:t];
    }));
}


// =================================================================================================================
// ITEM 6: extended protocols (+contextProtocol / +queryProtocol) made SAFE.   DONE (guarded) / UNSURE:see md 6.6
//
// This section REPLACES "Section 0" of group2-layout-data.hooks.m (do not %init both: two hooks of the same class
// methods would each build a different protocol and the second would win silently).  What it changes against group2:
//   * only selectors whose type encoding is known to be in SpringBoard's static trampoline table are put in the
//     protocols (an encoding that is missing makes the stock +initialize abort: SBChainableModifierMethodCache*
//     TrampolineForMethod has no fallback);
//   * the three 162 query selectors whose encoding is NOT in the 16.0 table are answered by plain methods on
//     SBSwitcherModifier that walk the query chain themselves (BP2B_SetupProtocolFallbacks);
//   * installed from BP2B_Early() with a crash-loop breadcrumb, the initialisation is forced and verified,
//     and every assumption is re-checked (BP2B_ProtocolsOK()).
// 16.0 facts (20A8372) this relies on, all read from the disassembly:
//   +[SBChainableModifier initialize] (0x1c6428068) is a tail call to [self _initalizeIMPCaching] (0x1c642a6c0).
//   _initalizeIMPCaching, when self == [self baseClassForQueryProtocol] (the topmost class defining +queryProtocol:
//   SBSwitcherModifier): for each protocol level starting at +queryProtocol (then +contextProtocol): required instance
//   methods (protocol_copyMethodDescriptionList(p, YES, YES)): if [self instancesRespondToSelector:] -> assertion
//   "Cannot implement %@ on an implementer of +queryProtocol"; else class_addMethod(self, sel, trampolineForTypes) with
//   _SBChainableModifierMethodCache{Query,Context}TrampolineForMethod; then protocol_copyProtocolList: >1 parents ->
//   assertion "Multiple sub protocols not currently supported".  The trampoline table (81 entries) is static.
// =================================================================================================================

#include <sys/sysctl.h>
#include <stdio.h>

// The 81 encodings of the 20A8372 table (0x1e16f1de0), in table order.
static const char *const kBP2B_Tramp160[] = {
    "@16@0:8",
    "@24@0:8@16",
    "@24@0:8Q16",
    "B16@0:8",
    "B24@0:8Q16",
    "q16@0:8",
    "Q16@0:8",
    "Q24@0:8Q16",
    "d16@0:8",
    "d24@0:8Q16",
    "{_NSRange=QQ}16@0:8",
    "{CGRect={CGPoint=dd}{CGSize=dd}}24@0:8Q16",
    "{UIRectCornerRadii=dddd}24@0:8Q16",
    "{CGRect={CGPoint=dd}{CGSize=dd}}16@0:8",
    "{CGPoint=dd}16@0:8",
    "{CGSize=dd}16@0:8",
    "B24@0:8@16",
    "{CGRect={CGPoint=dd}{CGSize=dd}}24@0:8@16",
    "d24@0:8@16",
    "{CGRect={CGPoint=dd}{CGSize=dd}}32@0:8q16q24",
    "v24@0:8@16",
    "{CGPoint=dd}32@0:8@16d24",
    "q24@0:8@16",
    "Q24@0:8@16",
    "{CGPoint=dd}32@0:8Q16q24",
    "{CGPoint=dd}48@0:8{CGPoint=dd}16{CGPoint=dd}32",
    "v16@0:8",
    "{CGPoint=dd}96@0:8{CGPoint=dd}16{CGPoint=dd}32{CGPoint=dd}48{CGPoint=dd}64N^d80N^d88",
    "{CGPoint=dd}40@0:8@16{CGPoint=dd}24",
    "@32@0:8@16@24",
    "{CGRect={CGPoint=dd}{CGSize=dd}}40@0:8q16@24q32",
    "{CGRect={CGPoint=dd}{CGSize=dd}}32@0:8q16@24",
    "B32@0:8@16Q24",
    "{UIRectCornerRadii=dddd}32@0:8q16@24",
    "@32@0:8q16@24",
    "B32@0:8q16@24",
    "@40@0:8@16{CGPoint=dd}24",
    "{CGSize=dd}24@0:8@16",
    "B32@0:8@16@24",
    "@40@0:8@16{CGSize=dd}24",
    "{CGSize=dd}40@0:8{CGSize=dd}16@32",
    "d32@0:8q16@24",
    "@48@0:8q16@24{CGPoint=dd}32",
    "q32@0:8q16@24",
    "d32@0:8q16Q24",
    "q24@0:8Q16",
    "Q40@0:8Q16q24@32",
    "{CGPoint=dd}24@0:8Q16",
    "{CGAffineTransform=dddddd}32@0:8{CGSize=dd}16",
    "{CGRect={CGPoint=dd}{CGSize=dd}}32@0:8@16@24",
    "d32@0:8@16@24",
    "{SBSwitcherAsyncRenderingAttributes=BB}24@0:8@16",
    "d40@0:8q16@24Q32",
    "d36@0:8@16d24B32",
    "{SBSwitcherShelfPresentationAttributes=B{CGRect={CGPoint=dd}{CGSize=dd}}QQ}24@0:8@16",
    "Q32@0:8q16@24",
    "B40@0:8q16@24Q32",
    "{CGPoint=dd}32@0:8q16@24",
    "{CGPoint=dd}24@0:8@16",
    "{CGPoint=dd}32@0:8q16Q24",
    "B40@0:8Q16{CGPoint=dd}24",
    "{CGRect={CGPoint=dd}{CGSize=dd}}56@0:8Q16{CGRect={CGPoint=dd}{CGSize=dd}}24",
    "{CGRect={CGPoint=dd}{CGSize=dd}}64@0:8q16@24{CGRect={CGPoint=dd}{CGSize=dd}}32",
    "{CGPoint=dd}112@0:8q16Q24{CGRect={CGPoint=dd}{CGSize=dd}}32{CGPoint=dd}64{CGRect={CGPoint=dd}{CGSize=dd}}80",
    "B48@0:8q16Q24{CGPoint=dd}32",
    "{CGRect={CGPoint=dd}{CGSize=dd}}72@0:8q16@24q32{CGRect={CGPoint=dd}{CGSize=dd}}40",
    "{CGRect={CGPoint=dd}{CGSize=dd}}32@0:8@16q24",
    "{UIRectCornerRadii=dddd}64@0:8q16@24{UIRectCornerRadii=dddd}32",
    "Q40@0:8q16@24Q32",
    "d32@0:8Q16d24",
    "Q32@0:8@16Q24",
    "c24@0:8@16",
    "{CGSize=dd}32@0:8q16@24",
    "{CGRect={CGPoint=dd}{CGSize=dd}}72@0:8q16@24{CGRect={CGPoint=dd}{CGSize=dd}}32q64",
    "{CGSize=dd}64@0:8q16@24{CGRect={CGPoint=dd}{CGSize=dd}}32",
    "{CGRect={CGPoint=dd}{CGSize=dd}}56@0:8{CGRect={CGPoint=dd}{CGSize=dd}}16@48",
    "{CGPoint=dd}40@0:8{CGPoint=dd}16@32",
    "d32@0:8@16d24",
    "{SBSwitcherGradientWallpaperAttributes=dd}24@0:8Q16",
    "Q32@0:8@16@24",
    "B36@0:8@16@24B32"
};

typedef struct { const char *sel; const char *types; } BP2BProtoSpec;
// 16.2 context-protocol additions (final provider = the VC; all already implemented by group2 section A2).
static const BP2BProtoSpec kBP2B_PCtx[] = {
    { "appLayoutOnContinuousExposeStage",                         "@16@0:8" },
    { "continuousExposeIdentifiersGenerationCount",               "Q16@0:8" },
    { "continuousExposeIdentifiersInStrip",                       "@16@0:8" },
    { "continuousExposeIdentifiersInSwitcher",                    "@16@0:8" },
    { "continuousExposeStripProgress",                            "d16@0:8" },
    { "continuousExposeStripTongueBackdropCaptureLayoutElement",  "@16@0:8" },
    { "draggingAppLayoutsForContinuousExposeWindowDrag",          "@16@0:8" },
    { "layoutRestrictionInfoForItem:",                            "@24@0:8@16" },
    { "newContinuousExposeIdentifiersGenerationCount",            "Q16@0:8" },
    { "proposedAppLayoutsForContinuousExposeWindowDrag",          "@16@0:8" },
    { "requireStripContentsInViewHierarchy",                      "B16@0:8" },
    { "supportedContentInterfaceOrientationsForItem:",            "Q24@0:8@16" },
};
// 16.2 query-protocol additions that have a trampoline in 16.0.
static const BP2BProtoSpec kBP2B_PQry[] = {
    { "activeLeafAppLayoutsReachableByKeyboardShortcut",          "@16@0:8" },
    { "canSelectLeafWithModifierKeysInAppLayout:",                "B24@0:8@16" },
    { "inactiveAppLayoutsReachableByKeyboardShortcut",            "@16@0:8" },
    { "shouldAllowGroupOpacityForAppLayout:",                     "B24@0:8@16" },
    { "adjustedContinuousExposeIdentifiersInStripFromPreviousIdentifiersInStrip:", "@24@0:8@16" },
    { "adjustedContinuousExposeIdentifiersInSwitcherFromPreviousIdentifiersInSwitcher:identifiersInStrip:", "@32@0:8@16@24" },
    { "isContinuousExposeStripVisible",                           "B16@0:8" },
    { "proposedAppLayoutForContinuousExposeWindowDrag",           "@16@0:8" },
    { "spaceAccessoryViewIconHitTestOutsetForAppLayout:",         "d24@0:8@16" },
    { "wantsContinuousExposeHoverGesture",                        "B16@0:8" },
};
// 16.2 query selectors with NO trampoline in 16.0 (encodings new in 16.2).  Never put in a protocol.
static const BP2BProtoSpec kBP2B_PNoChain[] = {
    { "adjustedSpaceAccessoryViewScale:forAppLayout:",            "d32@0:8d16@24" },
    { "clippingFrameForLayoutRole:inAppLayout:atIndex:withBounds:",
      "{CGRect={CGPoint=dd}{CGSize=dd}}72@0:8q16@24Q32{CGRect={CGPoint=dd}{CGSize=dd}}40" },
    { "continuousExposeStripTongueAttributes",                    "{SBSwitcherContinuousExposeStripTongueAttributes=QQ}16@0:8" },
};

static BOOL gBP2B_ProtoOK = NO;                       // set by BP2B_VerifyProtocols
static BOOL gBP2B_ProtoTried = NO;
static NSMutableArray<NSString *> *gBP2B_ProtoAdded;  // "sel|types" actually registered
static NSMutableArray<NSString *> *gBP2B_ProtoSkipped;
static IMP gBP2B_OrigCtxProto, gBP2B_OrigQryProto;
static Protocol *gBP2B_ExtCtx, *gBP2B_ExtQry;

BOOL BP2B_ProtocolsOK(void) { return gBP2B_ProtoOK; }

static BOOL BP2B_BuildIs20A8372(void) {
    char buf[64] = {0}; size_t len = sizeof buf - 1;
    if (sysctlbyname("kern.osversion", buf, &len, NULL, 0) != 0) return NO;
    return strcmp(buf, "20A8372") == 0;
}

// Encodings that the STOCK protocols of this build already use: the stock +initialize built trampolines for all of them,
// so they are in the table on every build (dynamic whitelist, build independent).
static void BP2B_CollectEncodings(Protocol *p, NSMutableSet<NSString *> *out, int depth) {
    if (!p || depth > 8) return;
    unsigned n = 0;
    struct objc_method_description *ms = protocol_copyMethodDescriptionList(p, YES, YES, &n);
    for (unsigned i = 0; i < n; i++) if (ms[i].types) [out addObject:@(ms[i].types)];
    free(ms);
    unsigned pc = 0;
    Protocol * __unsafe_unretained *pl = protocol_copyProtocolList(p, &pc);
    for (unsigned i = 0; i < pc; i++) BP2B_CollectEncodings(pl[i], out, depth + 1);
    free(pl);
}

static BOOL BP2B_StaticTableHas(const char *enc) {
    for (size_t i = 0; i < sizeof kBP2B_Tramp160 / sizeof kBP2B_Tramp160[0]; i++)
        if (strcmp(kBP2B_Tramp160[i], enc) == 0) return YES;
    return NO;
}

static BOOL BP2B_ProtoHasSel(Protocol *p, SEL s) {
    for (int d = 0; p && d < 8; d++) {
        struct objc_method_description md = protocol_getMethodDescription(p, s, YES, YES);
        if (md.name) return YES;
        unsigned pc = 0;
        Protocol * __unsafe_unretained *pl = protocol_copyProtocolList(p, &pc);
        Protocol *next = pc ? pl[0] : nil;
        free(pl);
        p = next;
    }
    return NO;
}

// Same shape as group2's builder (copy of `base`'s own required methods + adds, same single parent) but filtered:
// an addition is dropped when (a) its encoding is not provably in the trampoline table, (b) the selector is already in
// the protocol chain, (c) SBSwitcherModifier/SBChainableModifier already respond to it (the stock +initialize would assert).
static Protocol *BP2B_BuildProto(Protocol *base, const char *name, const BP2BProtoSpec *adds, size_t nAdds, Class owner) {
    if (!base) return nil;
    Protocol *existing = objc_getProtocol(name);
    if (existing) return existing;
    BOOL known = BP2B_BuildIs20A8372();
    NSMutableSet<NSString *> *dyn = [NSMutableSet set];
    BP2B_CollectEncodings(base, dyn, 0);
    unsigned pc = 0;
    Protocol * __unsafe_unretained *pl = protocol_copyProtocolList(base, &pc);
    if (pc > 1) { free(pl); return nil; }                       // the stock walker asserts on this; leave everything alone
    Protocol *np = objc_allocateProtocol(name);
    if (!np) { free(pl); return nil; }
    for (unsigned i = 0; i < pc; i++) protocol_addProtocol(np, pl[i]);
    free(pl);
    unsigned n = 0;
    struct objc_method_description *ms = protocol_copyMethodDescriptionList(base, YES, YES, &n);
    for (unsigned i = 0; i < n; i++) protocol_addMethodDescription(np, ms[i].name, ms[i].types, YES, YES);
    free(ms);
    ms = protocol_copyMethodDescriptionList(base, NO, YES, &n);
    for (unsigned i = 0; i < n; i++) protocol_addMethodDescription(np, ms[i].name, ms[i].types, NO, YES);
    free(ms);
    for (size_t i = 0; i < nAdds; i++) {
        SEL s = sel_registerName(adds[i].sel);
        NSString *tag = [NSString stringWithFormat:@"%s|%s", adds[i].sel, adds[i].types];
        BOOL encOK = [dyn containsObject:@(adds[i].types)] || (known && BP2B_StaticTableHas(adds[i].types));
        if (!encOK) { [gBP2B_ProtoSkipped addObject:[tag stringByAppendingString:@"|encoding-not-in-table"]]; continue; }
        if (BP2B_ProtoHasSel(base, s)) { [gBP2B_ProtoSkipped addObject:[tag stringByAppendingString:@"|already-in-protocol"]]; continue; }
        if (owner && [owner instancesRespondToSelector:s]) { [gBP2B_ProtoSkipped addObject:[tag stringByAppendingString:@"|class-implements"]]; continue; }
        protocol_addMethodDescription(np, s, adds[i].types, YES, YES);
        [gBP2B_ProtoAdded addObject:tag];
    }
    objc_registerProtocol(np);
    return np;
}

// True when the stock +initialize already ran for SBSwitcherModifier (its own method list then contains the trampolines).
static BOOL BP2B_ProtocolsAlreadyInstalled(Class sm) {
    if (!sm) return NO;
    SEL probe = sel_registerName("animationAttributesForLayoutElement:");   // required query method, never implemented by the class itself
    unsigned n = 0;
    Method *ml = class_copyMethodList(sm, &n);
    BOOL found = NO;
    for (unsigned i = 0; i < n && !found; i++) if (method_getName(ml[i]) == probe) found = YES;
    free(ml);
    return found;
}

// Post-init check: every selector we registered has the trampoline (own method of SBSwitcherModifier, same types) and
// the protocol the class now reports is ours.
static BOOL BP2B_VerifyProtocols(Class sm) {
    if (!sm || !gBP2B_ProtoAdded) return NO;
    if (!BP2B_ProtocolsAlreadyInstalled(sm)) return NO;              // initialisation did not run
    for (NSString *tag in gBP2B_ProtoAdded) {
        NSArray<NSString *> *p = [tag componentsSeparatedByString:@"|"];
        Method m = class_getInstanceMethod(sm, sel_registerName(p[0].UTF8String));
        if (!m) return NO;
        const char *t = method_getTypeEncoding(m);
        if (!t || strcmp(t, p[1].UTF8String) != 0) return NO;
    }
    id q = BP2B_Obj((id)sm, sel_registerName("queryProtocol"));
    id c = BP2B_Obj((id)sm, sel_registerName("contextProtocol"));
    if (gBP2B_ExtQry && q && !protocol_isEqual((Protocol *)q, gBP2B_ExtQry)) return NO;
    if (gBP2B_ExtCtx && c && !protocol_isEqual((Protocol *)c, gBP2B_ExtCtx)) return NO;
    return YES;
}

static NSString *BP2B_CrumbPath(void) {
#ifdef BP_G2B_STANDALONE
    return @"/tmp/Backport162.proto.inflight";
#else
    return ROOT_PATH_NS(@"/tmp/Backport162.proto.inflight");
#endif
}
static NSString *BP2B_OffPath(void) {
#ifdef BP_G2B_STANDALONE
    return @"/tmp/Backport162.off.g2bproto";
#else
    return ROOT_PATH_NS(@"/tmp/Backport162.off.g2bproto");
#endif
}

// ---- the query-chain fallback used for the selectors that cannot be protocol members --------------------------------
// Query chain model (16.0): each modifier has -nextQueryModifier (ivar +0x40) = the next modifier of the query chain, and
// -enumerateChildModifiersWithBlock:.  A fallback call finds the first modifier at/after `me` whose class implements `sel`
// with an IMP other than this fallback and calls it (it may call [super sel], which re-enters this fallback with
// me = that modifier and continues behind it).  Nobody overrides -> 162 default (SBDefaultImplementationsSwitcherModifier).
static IMP gBP2B_FbScale, gBP2B_FbClip, gBP2B_FbTongue;

static id BP2B_FindOverriderInChildren(id m, SEL sel, IMP fallback, int *budget) {
    SEL en = sel_registerName("enumerateChildModifiersWithBlock:");
    if (!m || (*budget)-- <= 0 || ![m respondsToSelector:en]) return nil;
    NSMutableArray *kids = [NSMutableArray array];
    ((void (*)(id, SEL, id))objc_msgSend)(m, en, ^(id child) { if (child) [kids addObject:child]; });
    for (id child in [kids reverseObjectEnumerator]) {
        IMP i = class_getMethodImplementation(object_getClass(child), sel);
        if (i && i != fallback) return child;
        id r = BP2B_FindOverriderInChildren(child, sel, fallback, budget);
        if (r) return r;
    }
    return nil;
}

static id BP2B_FindOverrider(id me, SEL sel, IMP fallback) {
    SEL nextSel = sel_registerName("nextQueryModifier");
    id n = BP2B_Obj(me, nextSel);
    for (int g = 0; n && g < 512; g++) {
        IMP i = class_getMethodImplementation(object_getClass(n), sel);
        if (i && i != fallback) return n;
        n = BP2B_Obj(n, nextSel);
    }
    // UNSURE:nextQueryModifier may be nil on the root -> depth-first search of the child tree, last child (highest level) first
    int budget = 512;
    return BP2B_FindOverriderInChildren(me, sel, fallback, &budget);
}

static void BP2B_SetupProtocolFallbacks(void) {
    Class sm = objc_getClass("SBSwitcherModifier");
    if (!sm) return;
    // 162 default implementations: scale -> identity, clipping -> the bounds argument, tongue -> {0,0} (state "none").
    gBP2B_FbScale = imp_implementationWithBlock(^double(id me, double scale, id layout) {
        SEL s = sel_registerName("adjustedSpaceAccessoryViewScale:forAppLayout:");
        id n = BP2B_FindOverrider(me, s, gBP2B_FbScale);
        if (!n) return scale;
        return ((double (*)(id, SEL, double, id))class_getMethodImplementation(object_getClass(n), s))(n, s, scale, layout);
    });
    gBP2B_FbClip = imp_implementationWithBlock(^CGRect(id me, long long role, id layout, unsigned long long idx, CGRect bounds) {
        SEL s = sel_registerName("clippingFrameForLayoutRole:inAppLayout:atIndex:withBounds:");
        id n = BP2B_FindOverrider(me, s, gBP2B_FbClip);
        if (!n) return bounds;
        return ((CGRect (*)(id, SEL, long long, id, unsigned long long, CGRect))class_getMethodImplementation(object_getClass(n), s))(n, s, role, layout, idx, bounds);
    });
    typedef struct { unsigned long long state, direction; } BP2BTongueAttrs;
    gBP2B_FbTongue = imp_implementationWithBlock(^BP2BTongueAttrs(id me) {
        SEL s = sel_registerName("continuousExposeStripTongueAttributes");
        id n = BP2B_FindOverrider(me, s, gBP2B_FbTongue);
        BP2BTongueAttrs none = { 0, 0 };
        if (!n) return none;
        return ((BP2BTongueAttrs (*)(id, SEL))class_getMethodImplementation(object_getClass(n), s))(n, s);
    });
    // class_addMethod only: a later 16.0 or ported implementation on a subclass overrides, and an existing one is kept.
    BP2B_AddIfMissing(sm, "adjustedSpaceAccessoryViewScale:forAppLayout:", gBP2B_FbScale, kBP2B_PNoChain[0].types);
    BP2B_AddIfMissing(sm, "clippingFrameForLayoutRole:inAppLayout:atIndex:withBounds:", gBP2B_FbClip, kBP2B_PNoChain[1].types);
    BP2B_AddIfMissing(sm, "continuousExposeStripTongueAttributes", gBP2B_FbTongue, kBP2B_PNoChain[2].types);
}

// Called FIRST from the %ctor (before any %init of other groups, before anything messages SBSwitcherModifier).
void BP2B_Early(void) {
    if (gBP2B_ProtoTried) return;
    gBP2B_ProtoTried = YES;
    gBP2B_ProtoAdded = [NSMutableArray array];
    gBP2B_ProtoSkipped = [NSMutableArray array];
    if (!BP2B_Enabled("g2bproto")) { BP_Log(@"G2B: protocol extension disabled by switch"); return; }
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:BP2B_CrumbPath()]) {
        // the previous launch died inside the forced +initialize: switch the feature off for good
        [@"auto-disabled after crash" writeToFile:BP2B_OffPath() atomically:YES encoding:NSUTF8StringEncoding error:nil];
        [fm removeItemAtPath:BP2B_CrumbPath() error:nil];
        BP_Log(@"G2B: crumb found, protocol extension auto-disabled");
        return;
    }
    Class sm = objc_getClass("SBSwitcherModifier");
    Class cm = objc_getClass("SBChainableModifier");
    // shape check of the 16.0 mechanism
    if (!sm || !cm || !class_getClassMethod(cm, sel_registerName("_initalizeIMPCaching")) ||
        !class_getClassMethod(cm, sel_registerName("baseClassForQueryProtocol")) ||
        !class_getClassMethod(sm, sel_registerName("queryProtocol")) || !class_getClassMethod(sm, sel_registerName("contextProtocol"))) {
        BP_Log(@"G2B: chain mechanism not found, protocol extension off");
        return;
    }
    if (BP2B_ProtocolsAlreadyInstalled(sm)) { BP_Log(@"G2B: too late (SBSwitcherModifier already initialised): fallback route only"); return; }
    Class meta = object_getClass((id)sm);
    Method mq = class_getClassMethod(sm, sel_registerName("queryProtocol"));
    Method mc = class_getClassMethod(sm, sel_registerName("contextProtocol"));
    gBP2B_OrigQryProto = method_getImplementation(mq);
    gBP2B_OrigCtxProto = method_getImplementation(mc);
    const char *tq = method_getTypeEncoding(mq), *tc = method_getTypeEncoding(mc);
    // build once, inside the hooked class methods (first sent from the stock +initialize)
    class_replaceMethod(meta, sel_registerName("contextProtocol"), imp_implementationWithBlock(^id(id me) {
        id orig = gBP2B_OrigCtxProto ? ((id (*)(id, SEL))gBP2B_OrigCtxProto)(me, sel_registerName("contextProtocol")) : nil;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            gBP2B_ExtCtx = BP2B_BuildProto((Protocol *)orig, "BP162_SBSwitcherContextProviding", kBP2B_PCtx, sizeof kBP2B_PCtx / sizeof kBP2B_PCtx[0], objc_getClass("SBSwitcherModifier"));
        });
        return gBP2B_ExtCtx ?: orig;
    }), tc);
    class_replaceMethod(meta, sel_registerName("queryProtocol"), imp_implementationWithBlock(^id(id me) {
        id orig = gBP2B_OrigQryProto ? ((id (*)(id, SEL))gBP2B_OrigQryProto)(me, sel_registerName("queryProtocol")) : nil;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            gBP2B_ExtQry = BP2B_BuildProto((Protocol *)orig, "BP162_SBSwitcherMultitaskingQueryProviding", kBP2B_PQry, sizeof kBP2B_PQry / sizeof kBP2B_PQry[0], objc_getClass("SBSwitcherModifier"));
        });
        return gBP2B_ExtQry ?: orig;
    }), tq);
    // Force the stock initialisation NOW (deterministic order) under the breadcrumb.
    [@"1" writeToFile:BP2B_CrumbPath() atomically:YES encoding:NSUTF8StringEncoding error:nil];
    ((id (*)(id, SEL))objc_msgSend)((id)sm, sel_registerName("class"));      // +class on a class object runs +initialize first
    gBP2B_ProtoOK = BP2B_VerifyProtocols(sm);
    [fm removeItemAtPath:BP2B_CrumbPath() error:nil];
    BP_Log(@"G2B: protocols %s; added %lu skipped %lu", gBP2B_ProtoOK ? "OK" : "FAILED-verification",
           (unsigned long)gBP2B_ProtoAdded.count, (unsigned long)gBP2B_ProtoSkipped.count);
    for (NSString *s in gBP2B_ProtoSkipped) BP_Log(@"G2B: skipped %@", s);
}

// The final context provider for a modifier when the chain route is not available (gBP2B_ProtoOK == NO): the root's delegate.
static id BP2B_ContextProviderFor(id modifier) {
    id m = modifier;
    for (int g = 0; m && g < 64; g++) {
        id parent = BP2B_Obj(m, sel_registerName("parentModifier"));
        if (!parent) break;
        m = parent;
    }
    return BP2B_Obj(m, sel_registerName("delegate"));
}

// ---------------------------------------------------------------------------------------------- entry point
// Call order (from the tweak %ctor):  BP2B_Early();  <group2 setup that adds %new methods to the VC / models>;  BP2B_Setup();
void BP2B_Setup(void) {
    if (!BP2B_Enabled("g2b")) return;
    BP2B_SetupProtocolFallbacks();
    BP2B_SetupAttributes();
    BP2B_SetupCalculator();
    BP2B_SetupLayoutAppLayout();
    BP2B_SetupTapEvent();
    BP2B_SetupSelection();
    BP2B_SetupKeyboardNav();
    BP2B_SetupGestureNames();
    BP2B_SetupAperture();
    BP2B_SetupGrabberClick();
    BP2B_SetupContainerPointer();
    BP2B_SetupTongue();
    BP_Log(@"G2B: setup done (protocols %s)", gBP2B_ProtoOK ? "chain" : "fallback-route");
}
