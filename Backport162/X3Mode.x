// X3Mode.x : gap G3 / audit row D1 "monitor scale and mode choice" (specs/GAPS-IMPLEMENTED-0.7.9.md section G3).
// 16.0 = 20A8372, 16.2 = 20C65 (unslid cache addresses).  Switches: modecriteria, modebase, modelogical.  Setup: X3_Setup().  Log prefix "[x3]" (Backport162.debug only).
//
// What decides the mode, the pixel size and the point size of an extended display (monitor), in both builds:
//   SBSceneHostingDisplayController _ensureCADisplayUpToDate:completion: (16.0 0x1c5f48424, 16.2 0x1c73bce50) puts the CADisplay into the preferred mode / logical scale / point scale / overscan
//   (identical apply block 0x1c5f487e4 / 0x1c73bd2c0: setCurrentMode:, setOverscanAdjustment:, setLogicalScale:, setPointScale:, setDisplayProperties:), and
//   SBSceneHostingDisplayController transformDisplayConfiguration:withBuilder: (16.0 0x1c5f46bf8 -> policy 0x1c633981c, 16.2 0x1c73bb2b8) builds the FBSDisplayConfiguration SpringBoard publishes:
//   pixel size = logical scale x mode size, point size = pixel size / contents scale, current / preferred mode = a copy of a mode with that size and scale.
// 16.0 splits the inputs over the policy (SBSystemShellExtendedDisplayControllerPolicy: _preferredModeForDisplayForTargetCADisplay: 0x1c633a954, _preferredSizeInPixels... 0x1c633a7a8,
// _preferredSizeInPoints... 0x1c633a890 = pixels / _preferredContentsScale, _preferredContentsScale 0x1c633a94c) and the controller (_preferredLogicalScale 0x1c5f48360); 16.2 moves them
// into one value, SBSceneHostingDisplayPreferences (policy displayPreferencesForDisplayController: 0x1c77dd034; the controller reads logicalScale / contentsScale / CADisplayModeCriteria
// / displayConfigurationRequest from it).  The restructure changes the result in three places (the arithmetic is the same: the per axis clamp is already in 16.0 _preferredLogicalScale
// 0x1c5f48360 and, for the published size, in Tweak.x switch "scale"):
//
//  1. The mode.  16.0 asks the CADisplay for [display preferredModeWithCriteria:[[CADisplayModeCriteria alloc] init]] (policy 0x1c633a954: no resolution, no refresh rate, hdrMode nil =
//     QuartzCore HDR type 0 "no preference").  16.2 builds the criteria from a fresh FBSMutableDisplayConfigurationRequest (SBSceneHostingDisplayPreferences init 0x1c788f4f4):
//     resolution = request.nativePixelSize ((0,0)), refreshRate = request.refreshRate (0), hdrMode = _FBSDisplayHDRModeToCADisplayHDRMode(request.hdrMode) = kCADisplayModeSDR for the
//     default 0 (FrontBoardServices 16.0 0x19c64736c / 16.2 0x19caf2a80).  QuartzCore -[CADisplay preferredModeWithCriteria:] (16.0 0x188446048, 16.2 0x188572570) is the same code
//     apart from one extra argument to create_mode, and passes hdr type 1 (SDR) instead of 0 to ModeSet::preferred_mode_with_criteria, so the mode list walk can end on another mode on a
//     monitor that offers HDR modes.  Port (switch modecriteria): -_preferredModeForDisplayForTargetCADisplay: builds the 16.2 criteria and asks the display.  It feeds
//     _preferredSizeInPixels / Points..., the policy's preferredDisplayModeForDisplayController: and with it _ensureCADisplayUpToDate (the mode put on the CADisplay), i.e. exactly the 16.2 inputs.
//     When the SDR criteria find no mode the 16.0 answer is used and the line "[x3] ... no mode" is logged (last line of the guard, not a silent switch).
//  2. The base mode of the published configuration.  16.0 policy transform copies [config preferredMode]; 16.2 copies [config currentMode] (0x1c73bb548), i.e. the mode the CADisplay is
//     really in after _ensureCADisplayUpToDate, with the pixel size's override size and the contents scale (_copyWithOverrideSize:scale:), and passes the same copy as preferred mode,
//     otherModes nil (the 16.2 policy answers keepOtherModes NO).  Port (switch modebase): after the 16.0 transform, when the two modes differ, redo
//     setCurrentMode:preferredMode:otherModes: with the copy of the current mode (size = _preferredSizeInPoints..., scale = _preferredContentsScale, as in the 16.0 body).
//  3. The logical scale put on the CADisplay of a display type 2: 16.2 _ensureCADisplayUpToDate (0x1c73bcf28 .. 0x1c73bcf34) uses (1, 1) when [_caDisplay displayType] == 2 and only otherwise the
//     clamped scale; 16.0 _preferredLogicalScale clamps in every case.  Port (switch modelogical): -_preferredLogicalScale answers (1, 1) for display type 2.  (The published size of such a
//     display already is the mode size in Tweak.x "scale", 16.2 0x1c73bb4b8.)
//
// Not ported / unchanged (specs/GAPS-IMPLEMENTED-0.7.9.md G3): SBDisplayScaleMapping (the new initWithDisplayHardwareIdentifier:... API and the mode walk are logging only in both builds, the
// logicalScaleForDisplayScale: result is the same), the 16.2 SBSceneHostingDisplayPreferences class itself (its three consumers are covered above), -[CADisplayMode _initWithMode:display:rates:]
// and CAWindowServerDisplay maxLayerBandwidth (QuartzCore internals, live in the 16.0 QuartzCore of the system; nothing in SpringBoard to port), cloningSupported.
// Needs a device with a monitor: the monitor's mode (Settings > Displays or the log line) follows the SDR choice; on a monitor without HDR modes nothing changes.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import "BP.h"
#import "BPX.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

// declared so that ARC knows the copy family (+1) of the result
@interface NSObject (BPX3ModeCopy)
- (id)_copyWithOverrideSize:(CGSize)size scale:(double)scale;
@end

static IMP gX3OrigPreferredMode, gX3OrigTransform, gX3OrigLogicalScale;

// the 16.2 CADisplayModeCriteria of a default policy (SBSceneHostingDisplayPreferences init 0x1c788f4f4)
static id X3_Criteria(void) {
    Class rc = NSClassFromString(@"FBSMutableDisplayConfigurationRequest"), cc = NSClassFromString(@"CADisplayModeCriteria");
    if (!rc || !cc) return nil;
    id req = [[rc alloc] init];
    id crit = [[cc alloc] init];
    SEL sRes = sel_registerName("setResolution:"), sRate = sel_registerName("setRefreshRate:"), sHdr = sel_registerName("setHdrMode:");
    if (!req || !crit || ![crit respondsToSelector:sRes] || ![crit respondsToSelector:sRate] || ![crit respondsToSelector:sHdr]) return nil;
    CGSize res = [req respondsToSelector:sel_registerName("nativePixelSize")] ? ((CGSize (*)(id, SEL))objc_msgSend)(req, sel_registerName("nativePixelSize")) : CGSizeZero;
    double rate = [req respondsToSelector:sel_registerName("refreshRate")] ? ((double (*)(id, SEL))objc_msgSend)(req, sel_registerName("refreshRate")) : 0;
    long long hdr = BPX_LL0(req, "hdrMode");
    static id (*conv)(long long); static dispatch_once_t once;
    dispatch_once(&once, ^{ conv = (id (*)(long long))dlsym(RTLD_DEFAULT, "FBSDisplayHDRModeToCADisplayHDRMode"); });
    id hdrMode = conv ? conv(hdr) : (hdr == 0 ? @"SDR" : (hdr == 1 ? @"HDR10" : (hdr == 2 ? @"Dolby" : nil)));
    ((void (*)(id, SEL, CGSize))objc_msgSend)(crit, sRes, res);
    ((void (*)(id, SEL, double))objc_msgSend)(crit, sRate, rate);
    ((void (*)(id, SEL, id))objc_msgSend)(crit, sHdr, hdrMode);
    return crit;
}

// -[SBSystemShellExtendedDisplayControllerPolicy _preferredModeForDisplayForTargetCADisplay:] 16.0 0x1c633a954
static id X3_PreferredMode(id self, SEL _cmd, id display) {
    id orig = gX3OrigPreferredMode ? ((id (*)(id, SEL, id))gX3OrigPreferredMode)(self, _cmd, display) : nil;
    if (!display || !BP_OnName("modecriteria")) return orig;
    id crit = X3_Criteria();
    id m = crit ? BPX_Obj1(display, "preferredModeWithCriteria:", crit) : nil;
    if (!m) {
        BP_Log(@"[x3] criteria preferred mode: no mode for %@ (criteria %@), keeping the default criteria mode %@", display, crit, orig);
        return orig;
    }
    if (BP_LogEnabled() && ![m isEqual:orig]) BP_Log(@"[x3] criteria preferred mode %@ instead of %@", m, orig);
    return m;
}

// -[SBSystemShellExtendedDisplayControllerPolicy displayController:transformDisplayConfiguration:withBuilder:] 16.0 0x1c633981c (16.2 controller 0x1c73bb2b8)
static void X3_Transform(id self, SEL _cmd, id controller, id config, id builder) {
    if (gX3OrigTransform) ((void (*)(id, SEL, id, id, id))gX3OrigTransform)(self, _cmd, controller, config, builder);
    if (!builder || !config || !BP_OnName("modebase")) return;
    SEL sCur = sel_registerName("currentMode"), sPref = sel_registerName("preferredMode"), sCA = sel_registerName("immutableCADisplay");
    SEL sPts = sel_registerName("_preferredSizeInPointsForTargetCADisplay:"), sScale = sel_registerName("_preferredContentsScale");
    SEL sSet = sel_registerName("setCurrentMode:preferredMode:otherModes:"), sCopy = sel_registerName("_copyWithOverrideSize:scale:");
    id display = BPX_Obj0(config, "immutableCADisplay");
    id cur = BPX_Obj0(config, "currentMode"), pref = BPX_Obj0(config, "preferredMode");
    if (!display || !cur || ![config respondsToSelector:sCur] || ![config respondsToSelector:sPref] || ![config respondsToSelector:sCA]) return;
    if (cur == pref || [cur isEqual:pref]) return;                                   // same base mode: the 16.0 body already did what 16.2 does
    if (![self respondsToSelector:sPts] || ![self respondsToSelector:sScale] || ![builder respondsToSelector:sSet] || ![cur respondsToSelector:sCopy]) return;
    CGSize pts = ((CGSize (*)(id, SEL, id))objc_msgSend)(self, sPts, display);
    double scale = ((double (*)(id, SEL))objc_msgSend)(self, sScale);
    id mode = [cur _copyWithOverrideSize:pts scale:scale];
    if (!mode) return;
    ((void (*)(id, SEL, id, id, id))objc_msgSend)(builder, sSet, mode, mode, nil);
    BP_Log(@"[x3] published mode is a copy of the current mode %@ (16.0: of the preferred mode %@), size %.0fx%.0f scale %.1f", cur, pref, pts.width, pts.height, scale);
}

// -[SBSceneHostingDisplayController _preferredLogicalScale] 16.0 0x1c5f48360 (16.2 inlines the display type 2 case in _ensureCADisplayUpToDate 0x1c73bcf28)
static CGSize X3_LogicalScale(id self, SEL _cmd) {
    CGSize r = gX3OrigLogicalScale ? ((CGSize (*)(id, SEL))gX3OrigLogicalScale)(self, _cmd) : CGSizeMake(1, 1);
    if (!BP_OnName("modelogical")) return r;
    id display = BPX_IvarObj(self, "_caDisplay");
    if (display && BPX_LL0(display, "displayType") == 2 && (r.width != 1 || r.height != 1)) {
        BP_Log(@"[x3] logical scale %.3fx%.3f -> 1x1 for display type 2", r.width, r.height);
        return CGSizeMake(1, 1);
    }
    return r;
}

void X3_Setup(void) {
    Class pol = NSClassFromString(@"SBSystemShellExtendedDisplayControllerPolicy");
    Class ctl = NSClassFromString(@"SBSceneHostingDisplayController");
    const char *kMode = "_preferredModeForDisplayForTargetCADisplay:", *kTr = "displayController:transformDisplayConfiguration:withBuilder:", *kLs = "_preferredLogicalScale";
    BOOL ok = pol && ctl && class_getInstanceMethod(pol, sel_registerName(kMode)) && class_getInstanceMethod(pol, sel_registerName(kTr)) && class_getInstanceMethod(ctl, sel_registerName(kLs))
           && NSClassFromString(@"CADisplayModeCriteria");
    if (!ok) { BP_Log(@"[x3] monitor mode choice NOT installed (class or selector missing)"); return; }
    gX3OrigPreferredMode = BPX_Replace(pol, kMode, (IMP)X3_PreferredMode);
    gX3OrigTransform = BPX_Replace(pol, kTr, (IMP)X3_Transform);
    gX3OrigLogicalScale = BPX_Replace(ctl, kLs, (IMP)X3_LogicalScale);
    BP_Log(@"[x3] monitor mode choice installed (switches modecriteria, modebase, modelogical)");
}
#pragma clang diagnostic pop
