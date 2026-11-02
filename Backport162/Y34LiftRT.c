// Y34LiftRT.c : run time side shared by the recompiled 16.2 bodies (tools/a2c/liftdev.h): class and ivar lookup with runtime subclasses.
// A 16.2 class whose instances carry ivars the 16.0 class does not have (SBDeviceApplicationSceneClassicWrapperView: _appSwitcherDefaults, _chamoisEnabledObserver, _chamoisSettings,
// _canRasterize; SBDeviceApplicationSceneView: _snapshottingInfoAssertion, _currentHostView) is represented by a runtime subclass that adds them with the 16.2 names
// (Y34Ext.h creates it).  The recompiled code addresses every ivar by NAME (IVOFF), so it needs nothing else: lift_class_lookup answers the subclass for the 16.2 class name (the
// code allocates it), lift_ivoff_lookup searches the subclass first (class_getInstanceVariable also finds the inherited ivars).
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

void *lift_class_lookup(const char *name) {
    void *e = ext_for(name);
    return e ? e : lift_objc_getClass(name);
}

long lift_ivoff_lookup(const char *spec) {
    char cls[96]; const char *dot = strchr(spec, '.');
    if (!dot || (size_t)(dot - spec) >= sizeof cls) return -1;
    memcpy(cls, spec, (size_t)(dot - spec)); cls[dot - spec] = 0;
    void *c = lift_class_lookup(cls);          // the subclass when one is registered: finds its own ivars and every inherited one
    if (!c) return -1;
    void *iv = lift_class_getInstanceVariable(c, dot + 1);
    if (!iv) return -1;
    return (long)lift_ivar_getOffset(iv);
}
