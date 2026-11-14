// Y34Ext.h : runtime subclasses that carry the ivars a 16.2 class has and the 16.0 class lacks (see Y34LiftRT.c).  Header only, static inline, ARC translation units.
//   Y34_MakeExt(base, ext, ivars) allocates + registers the subclass; the caller registers it with lift_register_ext(base, ext) so the recompiled 16.2 code allocates it and finds the
//   ivars by name, adds the methods, and (for +allocWithZone: of the base class) swaps the allocation to it.
//   Runtime-added ivars are NOT managed by ARC / the runtime: object ivars are kept with a manual CFRetain (Y34_ObjSet / Y34_ObjRelease) and weak ivars with objc_storeWeak /
//   objc_destroyWeak (the subclass' .cxx_destruct does the release).
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "BP.h"

extern void lift_register_ext(const char *baseName, void *extClass);

typedef struct { const char *name; size_t size; uint8_t log2align; const char *type; } Y34IvarSpec;

static inline Class Y34_MakeExt(const char *baseName, const char *extName, const Y34IvarSpec *iv, int n) {
    Class base = objc_getClass(baseName);
    if (!base) { BP_Anomaly("y34", @"[y34] ext class %s: base class %s does not exist", extName, baseName); return Nil; }
    Class c = objc_allocateClassPair(base, extName, 0);
    if (!c) { BP_Anomaly("y34", @"[y34] ext class %s: objc_allocateClassPair failed (name taken?)", extName); return Nil; }
    for (int k = 0; k < n; k++) {
        if (!class_addIvar(c, iv[k].name, iv[k].size, iv[k].log2align, iv[k].type)) {
            BP_Anomaly("y34", @"[y34] ext class %s: class_addIvar %s failed", extName, iv[k].name);
            objc_disposeClassPair(c);
            return Nil;
        }
    }
    objc_registerClassPair(c);
    return c;
}

static inline void **Y34_IvarSlot(id o, Ivar iv) { return (void **)((char *)(__bridge void *)o + ivar_getOffset(iv)); }
static inline id Y34_ObjGet(id o, Ivar iv) { return o && iv ? (__bridge id)*Y34_IvarSlot(o, iv) : nil; }
// strong store by hand (the ivar was added with class_addIvar: unretained for the runtime)
static inline void Y34_ObjSet(id o, Ivar iv, id v) {
    if (!o || !iv) return;
    void **p = Y34_IvarSlot(o, iv);
    void *old = *p;
    *p = v ? (void *)CFBridgingRetain(v) : NULL;
    if (old) CFRelease(old);
}
static inline void Y34_ObjRelease(id o, Ivar iv) { Y34_ObjSet(o, iv, nil); }

// ---- class identity shims -------------------------------------------------------------------------------------------------------------------------------------------------
// 16.0 code (and logging) that asks an instance for its class must keep seeing the 16.0 class, not the runtime subclass: -class answers the base class and -isMemberOfClass: accepts
// both.  (isKindOfClass: / respondsToSelector: / object_getClass-based lookups need nothing: the subclass IS a kind of the base class.)
static Class gY34ShimBase[4], gY34ShimExt[4];
static int gY34ShimN;
static Class Y34_ShimBaseOf(id self) {
    Class c = object_getClass(self);
    for (int k = 0; k < gY34ShimN; k++) if (gY34ShimExt[k] == c) return gY34ShimBase[k];
    return c;
}
static Class Y34_ShimClass(id self, SEL _cmd) { return Y34_ShimBaseOf(self); }
static BOOL Y34_ShimIsMember(id self, SEL _cmd, Class k) { return k == Y34_ShimBaseOf(self) || k == object_getClass(self); }
static inline void Y34_AddIdentityShims(Class ext, Class base) {
    if (gY34ShimN >= 4) return;
    gY34ShimBase[gY34ShimN] = base; gY34ShimExt[gY34ShimN] = ext; gY34ShimN++;
    class_addMethod(ext, sel_registerName("class"), (IMP)Y34_ShimClass, "#@:");
    class_addMethod(ext, sel_registerName("isMemberOfClass:"), (IMP)Y34_ShimIsMember, "B@:#");
}
