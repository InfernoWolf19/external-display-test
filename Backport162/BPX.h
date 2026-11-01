// BPX.h : small helpers shared by the gap ports X2 .. X9 (specs/GAPS-IMPLEMENTED-0.7.9.md).  Header only, everything static inline (no unused-function warnings).
// Messages go through objc_msgSend with the exact C type of the selector; every helper tolerates a nil receiver and a receiver that does not implement the selector.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "BP.h"

#define BPX_LOG(...) do { if (BP_LogEnabled()) BP_Log(__VA_ARGS__); } while (0)

// object-returning, no argument / one object argument / two object arguments
static inline id BPX_Obj0(id o, const char *sel) {
    SEL s = sel_registerName(sel);
    if (!o) return nil;
    if (![o respondsToSelector:s]) { BP_SelMiss("sel-bpx", o, s); return nil; }
    return ((id (*)(id, SEL))objc_msgSend)(o, s);
}
static inline id BPX_Obj1(id o, const char *sel, id a) {
    SEL s = sel_registerName(sel);
    if (!o) return nil;
    if (![o respondsToSelector:s]) { BP_SelMiss("sel-bpx", o, s); return nil; }
    return ((id (*)(id, SEL, id))objc_msgSend)(o, s, a);
}
static inline id BPX_Obj2(id o, const char *sel, id a, id b) {
    SEL s = sel_registerName(sel);
    if (!o) return nil;
    if (![o respondsToSelector:s]) { BP_SelMiss("sel-bpx", o, s); return nil; }
    return ((id (*)(id, SEL, id, id))objc_msgSend)(o, s, a, b);
}
// BOOL / long long returns (never route a scalar through the id helpers: ARC would retain the bits)
static inline BOOL BPX_Bool0(id o, const char *sel) {
    SEL s = sel_registerName(sel);
    if (!o) return NO;
    if (![o respondsToSelector:s]) { BP_SelMiss("sel-bpx", o, s); return NO; }
    return ((BOOL (*)(id, SEL))objc_msgSend)(o, s);
}
static inline long long BPX_LL0(id o, const char *sel) {
    SEL s = sel_registerName(sel);
    if (!o) return 0;
    if (![o respondsToSelector:s]) { BP_SelMiss("sel-bpx", o, s); return 0; }
    return ((long long (*)(id, SEL))objc_msgSend)(o, s);
}
// void setters
static inline void BPX_SetObj1(id o, const char *sel, id a) {
    SEL s = sel_registerName(sel);
    if (!o) return;
    if (![o respondsToSelector:s]) { BP_SelMiss("sel-bpx", o, s); return; }
    ((void (*)(id, SEL, id))objc_msgSend)(o, s, a);
}
static inline void BPX_SetBool1(id o, const char *sel, BOOL a) {
    SEL s = sel_registerName(sel);
    if (!o) return;
    if (![o respondsToSelector:s]) { BP_SelMiss("sel-bpx", o, s); return; }
    ((void (*)(id, SEL, BOOL))objc_msgSend)(o, s, a);
}

// [SBApp windowSceneManager]: SBApp is the UIApplication of SpringBoard
static inline id BPX_App(void) {
    Class c = NSClassFromString(@"UIApplication");
    return c ? BPX_Obj0((id)c, "sharedApplication") : nil;
}
static inline id BPX_WindowSceneManager(void) { return BPX_Obj0(BPX_App(), "windowSceneManager"); }
static inline id BPX_MainWorkspace(void) {
    Class c = NSClassFromString(@"SBWorkspace");
    return c ? BPX_Obj0((id)c, "mainWorkspace") : nil;
}

// object ivar by name (nil unless the ivar exists and is an object)
static inline id BPX_IvarObj(id o, const char *name) {
    Ivar iv = o ? BP_IvarLookup(object_getClass(o), name) : NULL;
    return BP_ObjIvar(o, iv);
}

// Install `imp` as the implementation of `sel` on `cls` and return the IMP that was reachable before (own or inherited), or NULL when the method does not exist at all
// (then nothing is installed).  `types` is taken from the method that was found.
static inline IMP BPX_Replace(Class cls, const char *sel, IMP imp) {
    SEL s = sel_registerName(sel);
    Method m = cls ? class_getInstanceMethod(cls, s) : NULL;
    if (!m) return NULL;
    IMP orig = method_getImplementation(m);
    class_replaceMethod(cls, s, imp, method_getTypeEncoding(m));
    return orig;
}
