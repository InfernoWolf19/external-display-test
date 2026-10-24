// BPY.h : helpers shared by the delta-sweep ports Y1 .. Yn (specs/DELTA-SWEEP-0.7.9.md).  Header only, everything static inline.
// Each Y file installs itself from its own constructor (it cannot touch Tweak.x): the constructor checks the build (20A8372 only, like Tweak.x) and every
// feature has a Backport162.off.<switch> kill file (BP_OnName).  Y files are linked after Tweak.x, so their constructors run after its %ctor (all runtime classes
// of the other groups exist by then) and BPX_Replace returns the IMP that was current at that time (a hook of another group is called through).
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <sys/sysctl.h>
#import <string.h>
#import "BP.h"
#import "BPX.h"

#define BPY_LOG(...) do { if (BP_LogEnabled()) BP_Log(__VA_ARGS__); } while (0)

static inline BOOL BPY_BuildOK(void) {
    char buf[64] = {0};
    size_t n = sizeof buf;
    if (sysctlbyname("kern.osversion", buf, &n, NULL, 0) != 0) return NO;
    return strcmp(buf, "20A8372") == 0;
}
// typed message send: BPY_SEND(RET, (extra arg types), receiver, "selector", args...)   e.g. BPY_SEND(id, (id), o, "foo:", a)  /  BPY_SEND(BOOL, (), o, "isFoo")
#define BPY_SEND(RET, ARGTYPES, OBJ, SELNAME, ...) \
    ((RET (*) BPY_PROTO ARGTYPES)objc_msgSend)((OBJ), sel_registerName(SELNAME), ##__VA_ARGS__)
#define BPY_PROTO(...) (id, SEL, ##__VA_ARGS__)

static inline BOOL BPY_Responds(id o, const char *sel) { return o && [o respondsToSelector:sel_registerName(sel)]; }

// the connected window scenes as an array (nil-safe)
static inline NSArray *BPY_ConnectedScenes(void) {
    id set = BPX_Obj0(BPX_WindowSceneManager(), "connectedWindowScenes");
    return [set respondsToSelector:@selector(allObjects)] ? [set allObjects] : (NSArray *)set;
}
// window scene of a display identity (nil when not connected)
static inline id BPY_SceneForIdentity(id identity) { return BPX_Obj1(BPX_WindowSceneManager(), "windowSceneForDisplayIdentity:", identity); }
