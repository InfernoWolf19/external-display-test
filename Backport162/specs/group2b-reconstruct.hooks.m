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

#ifdef BP_G2B_STANDALONE
static BOOL BP_On(int f) { (void)f; return YES; }
static void BP_Log(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);
static void BP_Log(NSString *fmt, ...) { (void)fmt; }
#else
#import <rootless.h>
#import "BP.h"
#endif

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
static BOOL BP2B_Enabled(const char *name) {
    static char offAll[1100]; static dispatch_once_t once;
    dispatch_once(&once, ^{
#ifdef BP_G2B_STANDALONE
        snprintf(offAll, sizeof offAll, "/tmp/Backport162.off");
#else
        snprintf(offAll, sizeof offAll, "%s", ROOT_PATH_NS(@"/tmp/Backport162.off").fileSystemRepresentation);
#endif
    });
    static uint64_t next[16]; static BOOL last[16]; static char names[16][24]; static int nn;
    int idx = -1;
    for (int i = 0; i < nn; i++) if (strcmp(names[i], name) == 0) { idx = i; break; }
    if (idx < 0 && nn < 16) { idx = nn++; snprintf(names[idx], sizeof names[idx], "%s", name); }
    uint64_t t = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    if (idx >= 0 && t < next[idx]) return last[idx];
    char path[1200];
    snprintf(path, sizeof path, "%s.%s", offAll, name);
    BOOL on = access(offAll, F_OK) != 0 && access(path, F_OK) != 0;
    if (idx >= 0) { next[idx] = t + 1000000000ull; last[idx] = on; }
    return on;
}

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

