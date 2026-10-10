// Shared by G1B.x and G1C.x (static, so each translation unit has its own copy). Run-time class kit and typed senders of group 1b.
#ifndef BP_G1BKIT_H
#define BP_G1BKIT_H
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <string.h>
#import <unistd.h>
#import "BP.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wunused-variable"

// ------------------------------------------------------------------------------------------------ run-time class kit

typedef struct { const char *sel; IMP imp; const char *types; /* fallback encoding if no donor has the selector */ } G1BMethod;
typedef struct { const char *name; size_t size; uint8_t align; const char *enc; } G1BIvar;

// Encoding of `sel` taken from a class that declares it in 16.0 (so a query keeps the exact encoding the chain expects),
// else the fallback. PORTABLE.
static const char *G1B_TypesFor(SEL sel, const char *fallback) {
    static Class donors[5]; static dispatch_once_t once;
    dispatch_once(&once, ^{
        donors[0] = NSClassFromString(@"SBDefaultImplementationsSwitcherModifier");
        donors[1] = NSClassFromString(@"SBSwitcherModifier");
        donors[2] = NSClassFromString(@"SBTransitionSwitcherModifier");
        donors[3] = NSClassFromString(@"SBGestureSwitcherModifier");
        donors[4] = NSClassFromString(@"SBGestureRootSwitcherModifier");
    });
    for (int i = 0; i < 5; i++) {
        if (!donors[i]) continue;
        Method m = class_getInstanceMethod(donors[i], sel);
        if (m) return method_getTypeEncoding(m);
    }
    return fallback;
}

// Builds and registers a subclass. Returns Nil (and logs) if the name is already taken by a *real* class (then the real one is
// returned - this keeps the port inert on a build that has the class), if the superclass is missing, or on any failure.
// `queryChecks` (NULL-terminated) are selectors the superclass must answer (they are the ones we call via [super]).
static Class G1B_MakeClass(const char *name, Class sup, const G1BIvar *ivars, size_t nIvars,
                           const G1BMethod *meths, size_t nMeths, const char *protocolName, BOOL *outCreated) {
    if (outCreated) *outCreated = NO;
    Class existing = objc_getClass(name);
    if (existing) return existing;                        // 16.2+ (or already built): never shadow a real class
    if (!sup) { BP_Log(@"g1b: superclass for %s missing", name); return Nil; }
    (void)[sup class];                                    // run +initialize of the base first (sets up the chain machinery)
    Class cls = objc_allocateClassPair(sup, name, 0);
    if (!cls) { BP_Log(@"g1b: objc_allocateClassPair(%s) failed", name); return Nil; }
    for (size_t i = 0; i < nIvars; i++) {
        if (!class_addIvar(cls, ivars[i].name, ivars[i].size, ivars[i].align, ivars[i].enc)) {
            BP_Log(@"g1b: class_addIvar %s.%s failed", name, ivars[i].name);
            objc_disposeClassPair(cls);
            return Nil;
        }
    }
    for (size_t i = 0; i < nMeths; i++) {
        SEL s = sel_registerName(meths[i].sel);
        const char *t = G1B_TypesFor(s, meths[i].types);
        if (!t || !class_addMethod(cls, s, meths[i].imp, t)) {
            BP_Log(@"g1b: class_addMethod %s.%s failed", name, meths[i].sel);
            objc_disposeClassPair(cls);
            return Nil;
        }
    }
    if (protocolName) { Protocol *p = objc_getProtocol(protocolName); if (p) class_addProtocol(cls, p); }
    objc_registerClassPair(cls);
    if (outCreated) *outCreated = YES;
    return cls;
}

// A `[super sel]` is only safe if the superclass has an IMP (a query trampoline) for it; 16.2-only selectors have none in 16.0.
static BOOL G1B_HasSuper(Class sup, SEL sel) { return sup && class_getInstanceMethod(sup, sel) != NULL; }

static ptrdiff_t G1B_IvarOffset(Class cls, const char *name) {
    Ivar iv = cls ? class_getInstanceVariable(cls, name) : NULL;
    return iv ? ivar_getOffset(iv) : -1;
}

// [super sel:...] with the exact C signature (objc_msgSendSuper is not variadic on arm64: always cast).
#define G1B_SUPER(RET, SUP, OBJ, SEL_, ARGTYPES, ...) ({ \
    struct objc_super _g1b_s = { (__bridge __unsafe_unretained id)(__bridge void *)(OBJ), (SUP) }; \
    ((RET (*) ARGTYPES)objc_msgSendSuper)(&_g1b_s, (SEL_), ##__VA_ARGS__); })

// Object state of run-time classes (see the header comment).
#define G1B_GET(obj, key)      objc_getAssociatedObject((obj), &(key))
#define G1B_SET(obj, key, val) objc_setAssociatedObject((obj), &(key), (val), OBJC_ASSOCIATION_RETAIN_NONATOMIC)

// Typed message helpers. Safe by construction: an object that does not respond to the selector yields nil / 0 / NO instead of an
// "unrecognized selector" exception (a SpringBoard crash seen on 0.6.0 came from exactly such a send on a 16.0 event class).
static inline id G1B_Send0(id o, SEL s)                       { return (o && [o respondsToSelector:s]) ? ((id (*)(id, SEL))objc_msgSend)(o, s) : nil; }
static inline id G1B_Send1(id o, SEL s, id a)                 { return (o && [o respondsToSelector:s]) ? ((id (*)(id, SEL, id))objc_msgSend)(o, s, a) : nil; }
static inline long long G1B_SendLL0(id o, SEL s)              { return (o && [o respondsToSelector:s]) ? ((long long (*)(id, SEL))objc_msgSend)(o, s) : 0; }
static inline BOOL G1B_SendB0(id o, SEL s)                    { return (o && [o respondsToSelector:s]) ? ((BOOL (*)(id, SEL))objc_msgSend)(o, s) : NO; }
static inline BOOL G1B_SendB1(id o, SEL s, id a)              { return (o && [o respondsToSelector:s]) ? ((BOOL (*)(id, SEL, id))objc_msgSend)(o, s, a) : NO; }
static inline void G1B_SendV0(id o, SEL s)                   { if (o && [o respondsToSelector:s]) ((void (*)(id, SEL))objc_msgSend)(o, s); }   // for VOID selectors (G1B_Send0 would retain the stale x0)
static inline void G1B_SendV1(id o, SEL s, id a)              { if (o && [o respondsToSelector:s]) ((void (*)(id, SEL, id))objc_msgSend)(o, s, a); }
static inline void G1B_SendVLL(id o, SEL s, long long a)      { if (o && [o respondsToSelector:s]) ((void (*)(id, SEL, long long))objc_msgSend)(o, s, a); }

// SBAppendSwitcherModifierResponse(new, existing): exported by the 16.0 SpringBoard binary (nm: _SBAppendSwitcherModifierResponse).
typedef id (*G1BAppendFn)(id newResponse, id existing);
static id G1B_Append(id newResponse, id existing) {
    static G1BAppendFn fn; static dispatch_once_t once;
    dispatch_once(&once, ^{ fn = (G1BAppendFn)dlsym(RTLD_DEFAULT, "SBAppendSwitcherModifierResponse"); });
    if (!fn) return existing ?: newResponse;               // PARTIAL: without the helper the new response replaces nothing; callers check G1B_HaveAppend()
    return fn(newResponse, existing);
}
static BOOL G1B_HaveAppend(void) { return dlsym(RTLD_DEFAULT, "SBAppendSwitcherModifierResponse") != NULL; }


static double G1B_Dbl0(id o, SEL s) { return (o && [o respondsToSelector:s]) ? ((double (*)(id, SEL))objc_msgSend)(o, s) : 0.0; }

static id G1B_NewUpdateLayoutResponse(unsigned long long options, long long mode) {
    Class c = NSClassFromString(@"SBUpdateLayoutSwitcherEventResponse");
    SEL s = @selector(initWithOptions:updateMode:);
    if (!c || ![c instancesRespondToSelector:s]) return nil;
    return ((id (*)(id, SEL, unsigned long long, long long))objc_msgSend)([c alloc], s, options, mode);
}
static id G1B_AppendTo(id newR, id existing) { return newR ? G1B_Append(newR, existing) : existing; }

#pragma clang diagnostic pop
#endif
