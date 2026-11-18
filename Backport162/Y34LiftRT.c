// Y34LiftRT.c : run time side shared by the recompiled 16.2 bodies (tools/a2c/liftdev.h): class and ivar lookup with runtime subclasses.
// A 16.2 class whose instances carry ivars the 16.0 class does not have (SBDeviceApplicationSceneClassicWrapperView: _appSwitcherDefaults, _chamoisEnabledObserver, _chamoisSettings,
// _canRasterize; SBDeviceApplicationSceneView: _snapshottingInfoAssertion, _currentHostView) is represented by a runtime subclass that adds them with the 16.2 names
// (Y34Ext.h creates it).  The recompiled code addresses every ivar by NAME (IVOFF), so it needs nothing else: lift_class_lookup answers the subclass for the 16.2 class name (the
// code allocates it: class references stay the REAL class, only alloc of the base is redirected, see lift_msg_fix / lift_intercept), lift_ivoff_lookup searches the subclass first (class_getInstanceVariable also finds the inherited ivars).
#include "tools/a2c/liftdev.h"
#include <string.h>

#define Y34_EXT_MAX 16
static struct { char base[96]; void *ext; } gExt[Y34_EXT_MAX];
static int gExtN;

void lift_register_ext(const char *baseName, void *extClass) {
    if (gExtN >= Y34_EXT_MAX || !baseName || strlen(baseName) >= sizeof gExt[0].base) return;
    strcpy(gExt[gExtN].base, baseName);
    gExt[gExtN].ext = extClass;
    gExtN++;
}

static void *ext_for(const char *name) {
    for (int k = 0; k < gExtN; k++) if (strcmp(gExt[k].base, name) == 0) return gExt[k].ext;
    return 0;
}

// CLS(): ALWAYS the real class.  The code uses a class reference for type checks (objc_opt_isKindOfClass, isMemberOfClass:, class equality, SBSafeCast), where the 16.0 class is the right
// answer for every instance (an instance of the runtime subclass is a kind of it too); answering the subclass there made `sceneView isKindOfClass:` fail for every view that was not an
// exact instance of the subclass (crash: "Unsupported scene view provided to ...PlaceholderContentViewProvider").  The subclass is used ONLY to allocate (below).
void *lift_class_lookup(const char *name) { return lift_objc_getClass(name); }

// ---- allocation: alloc of a registered base class creates the runtime subclass --------------------------------------------------------------------------------------------------
static void *ext_of_class(void *cls) {
    for (int k = 0; k < gExtN; k++) if (lift_objc_getClass(gExt[k].base) == cls) return gExt[k].ext;
    return 0;
}
// called before every objc_msgSend of the recompiled code: a class method alloc / allocWithZone: / new sent to a registered base class goes to the subclass
void lift_msg_fix(uint64_t *X) {
    if (!gExtN) return;
    static void *sAlloc, *sAllocZ, *sNew;
    if (!sAlloc) { sAlloc = lift_sel_registerName("alloc"); sAllocZ = lift_sel_registerName("allocWithZone:"); sNew = lift_sel_registerName("new"); }
    void *sel = (void *)(uintptr_t)X[1];
    if (sel != sAlloc && sel != sAllocZ && sel != sNew) return;
    void *e = ext_of_class((void *)(uintptr_t)X[0]);
    if (e) X[0] = (uint64_t)(uintptr_t)e;
}
extern void *lift_objc_alloc_real(void *) __asm__("_objc_alloc");
extern void *lift_objc_allocWithZone_real(void *) __asm__("_objc_allocWithZone");
extern void *lift_objc_opt_new_real(void *) __asm__("_objc_opt_new");
extern void *lift_class_createInstance_real(void *, size_t) __asm__("_class_createInstance");
static void *lift_i_alloc(void *c) { void *e = ext_of_class(c); return lift_objc_alloc_real(e ? e : c); }
static void *lift_i_allocWithZone(void *c) { void *e = ext_of_class(c); return lift_objc_allocWithZone_real(e ? e : c); }
static void *lift_i_alloc_init(void *c) {
    void *o = lift_i_alloc(c);
    return ((void *(*)(void *, void *))lift_objc_msgSend)(o, lift_sel_registerName("init"));
}
static void *lift_i_opt_new(void *c) { void *e = ext_of_class(c); return lift_objc_opt_new_real(e ? e : c); }
static void *lift_i_createInstance(void *c, size_t extra) { void *e = ext_of_class(c); return lift_class_createInstance_real(e ? e : c, extra); }
// C entry points that allocate by class: the lifted code gets these instead of the runtime's
void *lift_intercept(const char *bare) {
    if (!gExtN) return 0;
    if (strcmp(bare, "objc_alloc") == 0) return (void *)lift_i_alloc;
    if (strcmp(bare, "objc_allocWithZone") == 0) return (void *)lift_i_allocWithZone;
    if (strcmp(bare, "objc_alloc_init") == 0) return (void *)lift_i_alloc_init;
    if (strcmp(bare, "objc_opt_new") == 0) return (void *)lift_i_opt_new;
    if (strcmp(bare, "class_createInstance") == 0) return (void *)lift_i_createInstance;
    return 0;
}

long lift_ivoff_lookup(const char *spec) {
    char cls[96]; const char *dot = strchr(spec, '.');
    if (!dot || (size_t)(dot - spec) >= sizeof cls) return -1;
    memcpy(cls, spec, (size_t)(dot - spec)); cls[dot - spec] = 0;
    void *c = ext_for(cls);                    // the subclass when one is registered: finds its own ivars and every inherited one
    if (!c) c = lift_class_lookup(cls);
    if (!c) return -1;
    void *iv = lift_class_getInstanceVariable(c, dot + 1);
    if (!iv) return -1;
    return (long)lift_ivar_getOffset(iv);
}

// ---- C functions that exist in the 16.2 frameworks only --------------------------------------------------------------------------------------------------------------------
typedef struct { double w, h; } LiftBuiltinSize;
// _BSSizeSwap (BaseBoard 16.2 0x18e5573b4): fmov d2, d0; fmov d0, d1; fmov d1, d2; ret
static LiftBuiltinSize lift_bi_BSSizeSwap(double w, double h) { LiftBuiltinSize r = { h, w }; return r; }
// _SBFIsChamoisWindowingUIAvailable (SpringBoardFoundation 16.2 0x18ee09820): the cached availability of the feature "SBChamoisWindowingUI".  16.0 computes the very same flag in
// SBFFeatureFlagsIsChamoisWindowingUIEnabled (16.0 SpringBoardFoundation 0x18eb692c4, what its switcher controller derives -isChamoisWindowingUIEnabled from); without both symbols the tweak
// runs on a Stage Manager device by construction, so YES (the same answer G1D.x gives).
static uint64_t lift_bi_SBFIsChamoisWindowingUIAvailable(void) {
    uint64_t (*fn)(void) = (uint64_t (*)(void))dlsym(RTLD_DEFAULT, "SBFFeatureFlagsIsChamoisWindowingUIEnabled");
    return fn ? (fn() & 1) : 1;
}
void *lift_builtin(const char *bare) {
    // class symbols (_OBJC_CLASS_$_Name, the receiver class of an objc_msgSendSuper2) are the Class object itself; dlsym of them fails for classes of the shared cache images on some builds
    if (strncmp(bare, "OBJC_CLASS_$_", 13) == 0) return lift_objc_getClass(bare + 13);
    if (strcmp(bare, "BSSizeSwap") == 0) return (void *)lift_bi_BSSizeSwap;
    if (strcmp(bare, "SBFIsChamoisWindowingUIAvailable") == 0) return (void *)lift_bi_SBFIsChamoisWindowingUIAvailable;
    return 0;
}
// symbol lookup for the Objective-C glue: the exported function, else the builtin
void *lift_symbol(const char *name) { return lift_gsym(name); }
