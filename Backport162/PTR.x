// PTR.x - pointeruid side of iPadOS 16.1 / 16.2 (multi display pointer rendering), loaded only into the pointeruid executable
// (Backport162PTR.plist: Filter Executables = pointeruid; arm64e only; build 20A8372 only).
// Spec: specs/POINTER-PIXELS-0.7.4.md (sections 3, 6). Compared real 16.0 pointeruid (user's file) with 16.1 / 16.2:
//   the transition / hide path is byte identical, 16.1 changed how the pointer layers are set up. Three of the four 16.1 changes are ported here,
//   per display AX zoom is skipped on purpose. Addresses are 16.0 / 16.1 / 16.2 of /System/Library/PrivateFrameworks/PointerUIServices.framework/Support/pointeruid.
//
// A (ptr_layerclass)  +[PUIDPointerShapeView layerClass]: 16.0 0x1000054b8 returns CABackdropLayer, 16.1 / 16.2 have no such method (plain CALayer).
//                     The gaussianBlur filter of the hide / show animation (-[PUIDPointerShapeView initWithFrame:] 16.0 0x100004390, setBlurRadius: 0x100004ca8) then acts
//                     on the pointer subtree instead of on a backdrop. Hook: return +[CALayer class] (what UIView's default gives 16.1 / 16.2).
// B (ptr_hidden)      16.1 hiddenForPerformanceReasons: -[PUIDDisplayContextFactoryImpl newDisplayContextForDisplay:pointerRenderingScene:systemPointerScene:]
//                     (16.0 0x100010c4c, 16.1 0x100010ac8: `cmp x20,#0; cset w23,ne` at 0x100010b60) passes (systemPointerScene != nil) to
//                     -[PUIDPointerRenderingRootViewController initWithDisplay:hiddenForPerformanceReasons:] (16.1 0x10001e7f0); its viewDidLoad (16.1 0x10001e9dc,
//                     0x10001ea70) does [self.view setHidden:hidden]. The pointer is then visible only through the system pointer window's _UIPortalView.
//                     16.0 has no such flag and nothing ever unhides the root view. Hook: the factory sets the system window first and the controller second
//                     (16.0 0x100010df4 setSystemPointerWindow:, 0x100010e00 setSystemPointerRenderingController:), so -[PUIDDisplayContext setSystemPointerRenderingController:]
//                     with a non-nil controller and a non-nil systemPointerWindow == "the display has a system pointer scene": hide the rendering controller's view there
//                     (its window is already un-hidden and the root view loaded by then, 0x100010d44). The factory itself is not hooked ("new" family: ARC +1 rules).
// C (ptr_scene)       nil systemPointerScene (16.1): the factory skips the system pointer window ("skipped creating system pointer window", 16.1 0x100010c40 cbz x20) and
//                     -[PUIDPointerController displayAttached:pointerRenderingScene:systemPointerScene:] (16.0 0x100008060, 16.1 0x100007ee0 `cbz x21` at 0x100007fac) skips
//                     the system client's portal source collection (createPointerPortalSourceCollectionForClient:, setShouldBeInvalidatedIfPointerLeavesDisplay:NO,
//                     setSystemPointerPortalSourceCollection:, hover region setPointerPortalSourceCollection:). Hooks: PUIDSystemPointerWindow initWithWindowScene: with a nil
//                     scene returns nil (no system window; the unused system controller of 16.0 stays, harmless), and displayAttached: with a nil system scene runs the 16.0 code
//                     with createPointerPortalSourceCollectionForClient: answering nil (the nil collection reaches exactly the setters 16.1 does not call, all nil safe:
//                     16.0 0x10001e188 isEqual/copy/portalLayer, hover region setter). Dead path on a normal setup: SpringBoard prepares both scenes for every display.
//
// Switches (checked at most once a second, in <jbroot>/tmp and /tmp; any access() failure means ON): Backport162.off.ptr_layerclass, .off.ptr_hidden, .off.ptr_scene, Backport162.off.
// A is evaluated when a shape view is created, B when a display context is created (display attach), C when a display attaches; a switch needs `killall pointeruid` to take
// effect on pointers that already exist.
// Log: NSLog with prefix [Backport162PTR]; additionally appended to <jbroot>/tmp/Backport162.log when Backport162.debug exists and the file is writable.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/dyld.h>
#import <sys/sysctl.h>
#import <string.h>
#import <stdio.h>
#import <unistd.h>
#import <fcntl.h>
#import <stdio.h>
#import <time.h>

@protocol BPPTRContext <NSObject>
- (id)systemPointerWindow;
- (id)pointerRenderingController;
@end

// ------------------------------------------------------------------------------------------------ switches / log

static const char *const kBPPTRDirs[2] = { "/var/jb/tmp", "/tmp" };

static BOOL BPPTR_FileExists(const char *name) {
    for (int i = 0; i < 2; i++) {
        char p[1200];
        snprintf(p, sizeof p, "%s/%s", kBPPTRDirs[i], name);
        if (access(p, F_OK) == 0) return YES;        // failure (ENOENT, sandbox EPERM) = not found = switch is not set
    }
    return NO;
}

typedef struct { uint64_t next; BOOL last; } BPPTRCache;

static BOOL BPPTR_Killed(BPPTRCache *c, const char *name) {
    uint64_t t = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    if (c->next && t < c->next) return c->last;
    c->next = t + 1000000000ull;
    c->last = BPPTR_FileExists("Backport162.off") || BPPTR_FileExists(name);
    return c->last;
}
static BOOL BPPTR_OnLayerClass(void) { static BPPTRCache c; return !BPPTR_Killed(&c, "Backport162.off.ptr_layerclass"); }
static BOOL BPPTR_OnHidden(void)     { static BPPTRCache c; return !BPPTR_Killed(&c, "Backport162.off.ptr_hidden"); }
static BOOL BPPTR_OnScene(void)      { static BPPTRCache c; return !BPPTR_Killed(&c, "Backport162.off.ptr_scene"); }

static void BPPTR_Log(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);
static void BPPTR_Log(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *m = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSLog(@"[Backport162PTR] %@", m);
    if (!BPPTR_FileExists("Backport162.debug")) return;
    for (int i = 0; i < 2; i++) {
        char p[1200];
        snprintf(p, sizeof p, "%s/Backport162.log", kBPPTRDirs[i]);
        if (access(p, W_OK) != 0 && access(kBPPTRDirs[i], W_OK) != 0) continue;
        FILE *f = fopen(p, "a");
        if (!f) continue;
        fprintf(f, "ptr: %s\n", m.UTF8String);
        fclose(f);
        break;
    }
}

// ------------------------------------------------------------------------------------------------ hooks

static __thread int gBPPTRNoPortal;      // >0 while displayAttached: runs for a display without system pointer scene

%group BPPTR_LayerClass
%hook PUIDPointerShapeView
+ (Class)layerClass {
    if (!BPPTR_OnLayerClass()) return %orig;
    return [CALayer class];
}
%end
%end

%group BPPTR_Hidden
%hook PUIDDisplayContext
- (void)setSystemPointerRenderingController:(id)controller {
    %orig;
    if (!controller || !BPPTR_OnHidden()) return;
    id<BPPTRContext> ctx = (id<BPPTRContext>)self;
    if (![ctx systemPointerWindow]) return;                              // 16.1: no system pointer scene -> not hidden
    UIViewController *rc = [ctx pointerRenderingController];
    if (![rc isKindOfClass:[UIViewController class]]) return;
    [rc.view setHidden:YES];                                             // 16.1 viewDidLoad: [self.view setHidden:_hiddenForPerformanceReasons]
    BPPTR_Log(@"hiddenForPerformanceReasons: pointer rendering view of %@ hidden (system pointer window present)", self);
}
%end
%end

%group BPPTR_Scene
%hook PUIDSystemPointerWindow
- (id)initWithWindowScene:(id)scene {
    if (!scene && BPPTR_OnScene()) {
        BPPTR_Log(@"skipped creating system pointer window (nil system pointer scene)");
        return nil;                                                      // 16.1 factory: `cbz x20` skips window + controller creation
    }
    return %orig;
}
%end

%hook PUIDPointerController
- (void)displayAttached:(id)display pointerRenderingScene:(id)renderingScene systemPointerScene:(id)systemScene {
    if (systemScene || !BPPTR_OnScene()) {
        %orig;
        return;
    }
    BPPTR_Log(@"displayAttached: nil system pointer scene, no system portal source collection (16.1 cbz)");
    gBPPTRNoPortal++;
    %orig;
    gBPPTRNoPortal--;
}
%end

%hook PUIDPointerRenderingRootViewController
- (id)createPointerPortalSourceCollectionForClient:(id)client {
    if (gBPPTRNoPortal > 0) return nil;
    return %orig;
}
%end
%end

// ------------------------------------------------------------------------------------------------ install

static BOOL BPPTR_BuildMatches(void) {
    char buf[64] = {0};
    size_t n = sizeof buf;
    if (sysctlbyname("kern.osversion", buf, &n, NULL, 0) != 0) return NO;
    return strcmp(buf, "20A8372") == 0;
}

static BOOL BPPTR_HasInstance(const char *cls, SEL sel) {
    Class c = objc_getClass(cls);
    return c && class_getInstanceMethod(c, sel) != NULL;
}

static BOOL gBPPTRDoneA, gBPPTRDoneB, gBPPTRDoneC;

// returns YES when everything is installed (or impossible)
static BOOL BPPTR_TryInstall(void) {
    if (!gBPPTRDoneA) {
        Class sv = objc_getClass("PUIDPointerShapeView");
        if (sv) {
            Method own = class_getClassMethod(sv, @selector(layerClass));
            Method base = class_getClassMethod([UIView class], @selector(layerClass));
            if (own && base && method_getImplementation(own) != method_getImplementation(base)) {
                %init(BPPTR_LayerClass);
                BPPTR_Log(@"ptr_layerclass installed (+[PUIDPointerShapeView layerClass] -> CALayer)");
            } else {
                BPPTR_Log(@"ptr_layerclass: PUIDPointerShapeView has no own layerClass, not installing");
            }
            gBPPTRDoneA = YES;
        }
    }
    if (!gBPPTRDoneB) {
        if (objc_getClass("PUIDDisplayContext")) {
            if (BPPTR_HasInstance("PUIDDisplayContext", @selector(setSystemPointerRenderingController:)) &&
                BPPTR_HasInstance("PUIDDisplayContext", @selector(systemPointerWindow)) &&
                BPPTR_HasInstance("PUIDDisplayContext", @selector(pointerRenderingController))) {
                %init(BPPTR_Hidden);
                BPPTR_Log(@"ptr_hidden installed");
            } else {
                BPPTR_Log(@"ptr_hidden: PUIDDisplayContext selectors missing, not installing");
            }
            gBPPTRDoneB = YES;
        }
    }
    if (!gBPPTRDoneC) {
        if (objc_getClass("PUIDPointerController") && objc_getClass("PUIDSystemPointerWindow") && objc_getClass("PUIDPointerRenderingRootViewController")) {
            if (BPPTR_HasInstance("PUIDPointerController", @selector(displayAttached:pointerRenderingScene:systemPointerScene:)) &&
                BPPTR_HasInstance("PUIDSystemPointerWindow", @selector(initWithWindowScene:)) &&
                BPPTR_HasInstance("PUIDPointerRenderingRootViewController", @selector(createPointerPortalSourceCollectionForClient:))) {
                %init(BPPTR_Scene);
                BPPTR_Log(@"ptr_scene installed");
            } else {
                BPPTR_Log(@"ptr_scene: selectors missing, not installing");
            }
            gBPPTRDoneC = YES;
        }
    }
    return gBPPTRDoneA && gBPPTRDoneB && gBPPTRDoneC;
}

static void BPPTR_RetryInstall(int attempt) {
    if (BPPTR_TryInstall()) return;
    if (attempt >= 100) {
        BPPTR_Log(@"classes still missing after %d attempts (A=%d B=%d C=%d), giving up", attempt, gBPPTRDoneA, gBPPTRDoneB, gBPPTRDoneC);
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(50 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{ BPPTR_RetryInstall(attempt + 1); });
}

// Marker so that the user can see whether the dylib was injected at all (one line per process start; the daemon may be sandboxed: then nothing is written).
static void BPPTR_Marker(const char *what) {
    const char *dirs[] = { "/var/jb/tmp", "/tmp", "/var/mobile/Library/Caches" };
    for (size_t i = 0; i < 3; i++) {
        char p[300]; snprintf(p, sizeof p, "%s/Backport162PTR.ctor", dirs[i]);
        int fd = open(p, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0644);
        if (fd < 0) continue;
        const char *img = _dyld_get_image_name(0);
        char line[600]; int n = snprintf(line, sizeof line, "pid %d image %s: %s\n", (int)getpid(), img ? img : "(null)", what);
        if (n > 0) (void)!write(fd, line, (size_t)n);
        close(fd);
        return;
    }
}

%ctor {
    @autoreleasepool {
        BPPTR_Marker("ctor entered");
        const char *path = _dyld_get_image_name(0);
        if (!path) return;
        size_t n = strlen(path);
        if (n < 11 || strcmp(path + n - 11, "/pointeruid") != 0) return;   // belt and braces next to the Filter
        if (!BPPTR_BuildMatches()) { BPPTR_Log(@"build does not match 20A8372, not installing"); return; }
        BPPTR_Log(@"loaded in pointeruid (20A8372)");
        BPPTR_RetryInstall(0);
    }
}
