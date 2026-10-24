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
// Added by specs/DISPLAY-LEFTOVERS-0.7.9.md item 3: the class stand-in BPSceneHostingDisplayPreferences (16.2 SBSceneHostingDisplayPreferences) with `displayPreferencesForDisplayController:` on both
// policies, the replacement of the controller's transformDisplayConfiguration:withBuilder: with the 16.2 body (criteria mode, per axis clamp, keepOtherModes, non interactive displays; switch
// modetransform) and setCloningSupported: / the non interactive policy factory (switch cloningsupported).
// Not ported / unchanged: SBDisplayScaleMapping (the new initWithDisplayHardwareIdentifier:... API and the mode walk are logging only in both builds, the logicalScaleForDisplayScale: result is the
// same), -[CADisplayMode _initWithMode:display:rates:] and CAWindowServerDisplay maxLayerBandwidth (QuartzCore internals, live in the 16.0 QuartzCore of the system; nothing in SpringBoard to port).
// Needs a device with a monitor: the monitor's mode (Settings > Displays or the log line) follows the SDR choice; on a monitor without HDR modes nothing changes.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <os/lock.h>
#import "BP.h"
#import "BPX.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

// declared so that ARC knows the copy family (+1) of the result
@interface NSObject (BPX3ModeCopy)
- (id)_copyWithOverrideSize:(CGSize)size scale:(double)scale;
@end

// ---------------------------------------------------------------------------------------------- SBSceneHostingDisplayPreferences (16.2 new class)
// 16.2 class SBSceneHostingDisplayPreferences : NSObject <NSCopying> (init 0x1c788f4f4, copyWithZone: 0x1c788f600, getters 0x1c788f638..0x1c788f658): the value a display policy
// answers to -displayPreferencesForDisplayController: (extended policy 0x1c77dd034, non interactive policy 0x1c78e9674) and the controller reads in -transformDisplayConfiguration:withBuilder:
// (0x1c73bb2b8) and -_ensureCADisplayUpToDate:completion: (0x1c73bce50).  ivars: keepOtherModes 0x8, request (copy) 0x10, contentsScale 0x18, CADisplayModeCriteria 0x20 (built in the
// init: resolution = request.nativePixelSize, refreshRate = request.refreshRate, hdrMode = _FBSDisplayHDRModeToCADisplayHDRMode(request.hdrMode)), logicalScale 0x28 / 0x30.
// 16.0 has no such class and its consumers do not ask for it; the class exists here under the BP prefix (a 16.0 runtime must not carry the 16.2 name), with the 16.2 selectors, and is
// used by the ported consumers below (the controller transform replacement and the criteria of the preferred mode).
@interface BPSceneHostingDisplayPreferences : NSObject <NSCopying>
- (instancetype)initWithDisplayConfigurationRequest:(id)request logicalScale:(CGSize)logicalScale contentsScale:(double)contentsScale keepOtherModes:(BOOL)keepOtherModes;
@property (nonatomic, readonly) id displayConfigurationRequest;
@property (nonatomic, readonly) CGSize logicalScale;
@property (nonatomic, readonly) double contentsScale;
@property (nonatomic, readonly) BOOL keepOtherModes;
@property (nonatomic, readonly) id CADisplayModeCriteria;
@end

@implementation BPSceneHostingDisplayPreferences {
    id _request;
    CGSize _logicalScale;
    double _contentsScale;
    BOOL _keepOtherModes;
    id _criteria;
}
- (instancetype)initWithDisplayConfigurationRequest:(id)request logicalScale:(CGSize)logicalScale contentsScale:(double)contentsScale keepOtherModes:(BOOL)keepOtherModes {
    if ((self = [super init])) {
        _request = [request copy];
        _logicalScale = logicalScale;
        _contentsScale = contentsScale;
        _keepOtherModes = keepOtherModes;
        Class cc = NSClassFromString(@"CADisplayModeCriteria");
        id crit = cc ? [[cc alloc] init] : nil;
        SEL sRes = sel_registerName("setResolution:"), sRate = sel_registerName("setRefreshRate:"), sHdr = sel_registerName("setHdrMode:");
        if (crit && [crit respondsToSelector:sRes] && [crit respondsToSelector:sRate] && [crit respondsToSelector:sHdr]) {
            CGSize res = [_request respondsToSelector:sel_registerName("nativePixelSize")] ? ((CGSize (*)(id, SEL))objc_msgSend)(_request, sel_registerName("nativePixelSize")) : CGSizeZero;
            double rate = [_request respondsToSelector:sel_registerName("refreshRate")] ? ((double (*)(id, SEL))objc_msgSend)(_request, sel_registerName("refreshRate")) : 0;
            long long hdr = BPX_LL0(_request, "hdrMode");
            static id (*conv)(long long); static dispatch_once_t once;
            dispatch_once(&once, ^{ conv = (id (*)(long long))dlsym(RTLD_DEFAULT, "FBSDisplayHDRModeToCADisplayHDRMode"); });
            id hdrMode = conv ? conv(hdr) : (hdr == 0 ? @"SDR" : (hdr == 1 ? @"HDR10" : (hdr == 2 ? @"Dolby" : nil)));
            ((void (*)(id, SEL, CGSize))objc_msgSend)(crit, sRes, res);
            ((void (*)(id, SEL, double))objc_msgSend)(crit, sRate, rate);
            ((void (*)(id, SEL, id))objc_msgSend)(crit, sHdr, hdrMode);
            _criteria = crit;
        }
    }
    return self;
}
- (id)copyWithZone:(NSZone *)zone { return self; }                      // 16.2 0x1c788f600 returns self (immutable value)
- (id)displayConfigurationRequest { return _request; }
- (CGSize)logicalScale { return _logicalScale; }
- (double)contentsScale { return _contentsScale; }
- (BOOL)keepOtherModes { return _keepOtherModes; }
- (id)CADisplayModeCriteria { return _criteria; }
@end

// 16.2 -[SBSystemShellExtendedDisplayControllerPolicy displayPreferencesForDisplayController:] 0x1c77dd034 (ivars: _displayModeSettings, _displayScaleMapping, _contentScale)
static id X3_ExtendedPolicyPrefs(id self, SEL _cmd, id controller) {
    Class rc = NSClassFromString(@"FBSMutableDisplayConfigurationRequest");
    id req = rc ? [[rc alloc] init] : nil;
    id ms = BPX_IvarObj(self, "_displayModeSettings"), map = BPX_IvarObj(self, "_displayScaleMapping");
    static long long (*overscan)(long long); static dispatch_once_t once;
    dispatch_once(&once, ^{ overscan = (long long (*)(long long))dlsym(RTLD_DEFAULT, "FBSDisplayOverscanCompensationForDisplayValue"); });
    SEL sOs = sel_registerName("setOverscanCompensation:");
    if (req && overscan && [req respondsToSelector:sOs]) ((void (*)(id, SEL, long long))objc_msgSend)(req, sOs, overscan(BPX_LL0(ms, "overscanCompensation")));
    SEL sLs = sel_registerName("logicalScaleForDisplayScale:");
    double logical = [map respondsToSelector:sLs] ? ((double (*)(id, SEL, long long))objc_msgSend)(map, sLs, BPX_LL0(ms, "scale")) : 1.0;
    double contents = 1.0;
    Ivar cs = class_getInstanceVariable(object_getClass(self), "_contentScale");
    if (cs) memcpy(&contents, (const char *)(__bridge const void *)self + ivar_getOffset(cs), sizeof contents);
    return [[BPSceneHostingDisplayPreferences alloc] initWithDisplayConfigurationRequest:req logicalScale:CGSizeMake(logical, logical) contentsScale:contents keepOtherModes:NO];
}
// 16.2 -[SBNonInteractiveDisplayControllerPolicy displayPreferencesForDisplayController:] 0x1c78e9674: the scene's own request, scales 1, other modes kept
static id X3_NonInteractivePolicyPrefs(id self, SEL _cmd, id controller) {
    id req = BPX_Obj0(BPX_Obj0(BPX_IvarObj(self, "_currentScene"), "uiClientSettings"), "displayConfigurationRequest");
    return [[BPSceneHostingDisplayPreferences alloc] initWithDisplayConfigurationRequest:req logicalScale:CGSizeMake(1, 1) contentsScale:1.0 keepOtherModes:YES];
}

static IMP gX3OrigPreferredMode, gX3OrigTransform, gX3OrigLogicalScale;

// the 16.2 CADisplayModeCriteria of a default policy (SBSceneHostingDisplayPreferences init 0x1c788f4f4, request = a fresh FBSMutableDisplayConfigurationRequest)
static id X3_Criteria(void) {
    Class rc = NSClassFromString(@"FBSMutableDisplayConfigurationRequest");
    id req = rc ? [[rc alloc] init] : nil;
    if (!req) return nil;
    return [[[BPSceneHostingDisplayPreferences alloc] initWithDisplayConfigurationRequest:req logicalScale:CGSizeMake(1, 1) contentsScale:1.0 keepOtherModes:NO] CADisplayModeCriteria];
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

// -[SBSceneHostingDisplayController transformDisplayConfiguration:withBuilder:] 16.2 0x1c73bb2b8, ported as a replacement of the 16.0 body (0x1c5f46bf8: ready signal && policy responds ->
// identity check -> [policy displayController:transformDisplayConfiguration:withBuilder:], which only the extended policy implements).  16.2 order:
//  1. [config.identity rootIdentity] isEqual: [_displayIdentity rootIdentity], else the 16.0 assertion ("being asked to transform a display config we know nothing about"): the 16.0 body runs;
//  2. [_readyToTransformDisplaysSignal hasBeenSignalled] NO: debug log, nothing is built;
//  3. prefs = [_policy displayPreferencesForDisplayController:self]; otherModes = prefs.keepOtherModes ? [config.availableModes mutableCopy] minus preferredMode and currentMode : nil;
//  4. mode = [config.immutableCADisplay preferredModeWithCriteria:prefs.CADisplayModeCriteria]; w x h = its size; logical scale = (1, 1) for display type 2, else prefs.logicalScale clamped PER
//     AXIS to [display minimumLogicalScale, maximumLogicalScale] (min(max, max(min, v))); pixel size = logical x (w, h); points = pixel / prefs.contentsScale;
//  5. [builder setCurrentMode:C preferredMode:C otherModes:otherModes] with C = [config.currentMode _copyWithOverrideSize:points scale:contentsScale];
//     [builder setPixelSize:pixel nativeBounds:{0,0,pixel} bounds:{0,0,points}];
//  6. overscan: c = prefs.request.overscanCompensation; overscanned = (c + 1) > 1 (unsigned: c is neither 0 nor -1); [builder setOverscanned:overscanned compensation:(overscanned ? c : 0) safeRatio:config.safeOverscanRatio].
// For the extended policy this is the arithmetic of the 16.0 chain with the ported fixes (Tweak.x `scale` clamp, modecriteria, modebase, modelogical); it additionally applies to the non
// interactive (mirrored) displays, whose published configuration 16.0 left untouched, and keeps their other modes (keepOtherModes = YES).  Switch modetransform (off = the 16.0 body + the three
// switches above).  When the criteria find no mode the 16.0 body runs (logged).
static IMP gX3OrigCtlTransform;
static void X3_CtlTransform(id self, SEL _cmd, id config, id builder) {
    typedef void (*Orig)(id, SEL, id, id);
    Orig orig = (Orig)gX3OrigCtlTransform;
    if (!BP_OnName("modetransform") || !config || !builder) { orig(self, _cmd, config, builder); return; }
    id own = BPX_Obj0(BPX_IvarObj(self, "_displayIdentity"), "rootIdentity");
    id theirs = BPX_Obj0(BPX_Obj0(config, "identity"), "rootIdentity");
    if (!own || !theirs || ![theirs isEqual:own]) { orig(self, _cmd, config, builder); return; }                 // 16.0 assertion path
    id signal = BPX_IvarObj(self, "_readyToTransformDisplaysSignal");
    if (!BPX_Bool0(signal, "hasBeenSignalled")) { BP_Log(@"[x3] transform of %@ skipped: display not ready to be transformed", own); return; }     // 16.2: log only
    id policy = BPX_IvarObj(self, "_policy");
    SEL sPrefs = sel_registerName("displayPreferencesForDisplayController:");
    id prefs = [policy respondsToSelector:sPrefs] ? ((id (*)(id, SEL, id))objc_msgSend)(policy, sPrefs, self) : nil;
    id display = BPX_Obj0(config, "immutableCADisplay");
    id criteria = [prefs respondsToSelector:@selector(CADisplayModeCriteria)] ? [(BPSceneHostingDisplayPreferences *)prefs CADisplayModeCriteria] : nil;
    id preferred = (display && criteria) ? BPX_Obj1(display, "preferredModeWithCriteria:", criteria) : nil;
    id cur = BPX_Obj0(config, "currentMode");
    SEL sCopy = sel_registerName("_copyWithOverrideSize:scale:"), sSet = sel_registerName("setCurrentMode:preferredMode:otherModes:");
    SEL sPix = sel_registerName("setPixelSize:nativeBounds:bounds:"), sOs = sel_registerName("setOverscanned:compensation:safeRatio:");
    if (![prefs isKindOfClass:[BPSceneHostingDisplayPreferences class]] || !preferred || !cur || ![cur respondsToSelector:sCopy] || ![builder respondsToSelector:sSet] || ![builder respondsToSelector:sPix] || ![builder respondsToSelector:sOs]) {
        BP_Log(@"[x3] transform of %@: preferences %@ / preferred mode %@ / current mode %@ not usable, the 16.0 body runs", own, prefs, preferred, cur);
        orig(self, _cmd, config, builder);
        return;
    }
    BPSceneHostingDisplayPreferences *pf = (BPSceneHostingDisplayPreferences *)prefs;
    NSMutableSet *others = nil;
    if (pf.keepOtherModes) {
        id avail = BPX_Obj0(config, "availableModes");
        id mc = [avail respondsToSelector:@selector(mutableCopy)] ? [avail mutableCopy] : nil;
        if ([mc respondsToSelector:@selector(removeObject:)]) {
            [mc removeObject:BPX_Obj0(config, "preferredMode")];
            [mc removeObject:cur];
            others = mc;
        }
    }
    double w = (double)((unsigned long long (*)(id, SEL))objc_msgSend)(preferred, sel_registerName("width"));
    double h = (double)((unsigned long long (*)(id, SEL))objc_msgSend)(preferred, sel_registerName("height"));
    double lx = 1, ly = 1;
    if (BPX_LL0(display, "displayType") != 2) {
        double mx = ((double (*)(id, SEL))objc_msgSend)(display, sel_registerName("maximumLogicalScale"));
        double mn = ((double (*)(id, SEL))objc_msgSend)(display, sel_registerName("minimumLogicalScale"));
        CGSize ls = pf.logicalScale;
        lx = MIN(mx, MAX(mn, ls.width));
        ly = MIN(mx, MAX(mn, ls.height));
    }
    double px = lx * w, py = ly * h, cs = pf.contentsScale;
    double ptsW = px / cs, ptsH = py / cs;
    id mode = [cur _copyWithOverrideSize:CGSizeMake(ptsW, ptsH) scale:cs];
    ((void (*)(id, SEL, id, id, id))objc_msgSend)(builder, sSet, mode, mode, others);
    ((void (*)(id, SEL, CGSize, CGRect, CGRect))objc_msgSend)(builder, sPix, CGSizeMake(px, py), CGRectMake(0, 0, px, py), CGRectMake(0, 0, ptsW, ptsH));
    long long c = BPX_LL0(pf.displayConfigurationRequest, "overscanCompensation");
    BOOL overscanned = ((unsigned long long)c + 1ull) > 1ull;
    CGSize ratio = [config respondsToSelector:sel_registerName("safeOverscanRatio")] ? ((CGSize (*)(id, SEL))objc_msgSend)(config, sel_registerName("safeOverscanRatio")) : CGSizeZero;
    ((void (*)(id, SEL, BOOL, long long, CGSize))objc_msgSend)(builder, sOs, overscanned, overscanned ? c : 0, ratio);
    BP_Log(@"[x3] transform of %@: mode %@ -> pixel %.0fx%.0f points %.0fx%.0f scale %.1f logical %.3fx%.3f other modes %lu", own, preferred, px, py, ptsW, ptsH, cs, lx, ly, (unsigned long)[others count]);
}

// ---------------------------------------------------------------------------------------------- setCloningSupported: / non interactive policy factory
// FBSDisplayConfigurationBuilder (FrontBoardServices): 16.0 has only -setCloningNotSupported (ivar _lock_noCloning, 16.0 0x19c62bae8); 16.2 adds -setCloningSupported: (0x19cad6920: under the
// lock _lock_cloningSupported = flag, _lock_cloningSet = YES) next to -setCloningNotSupported.  16.2's two policy factories call it:
//   SBSystemShellExtendedDisplayControllerPolicyFactory transformDisplayConfiguration:forControllersWithBuilder: 0x1c74e0548: uniqueIdentifier "com.apple.springboard.shellui", setUIKitMainLike,
//     setCloningSupported:NO  (16.0 0x1c6061288: the same with setCloningNotSupported: no difference);
//   SBNonInteractiveDisplayControllerPolicyFactory ...forControllersWithBuilder: 0x1c7941ee4: restricted = [config.identity isRestrictedAirPlayDisplay]; uniqueIdentifier = restricted ?
//     "com.apple.springboard.noninteractive.PA2D" : "com.apple.springboard.noninteractive"; setCloningSupported:!restricted  (16.0 0x1c648ba70: only the plain identifier, cloning untouched).
// The 16.0 provider (-[SBSceneHostingDisplayControllerProvider transformDisplayConfiguration:] 0x1c5ed2218) calls transformDisplayForControllersWithBuilder: (no config argument), so the hook takes
// the configuration from the builder's _configuration ivar (set by initWithConfiguration:).  Switch cloningsupported.
static IMP gX3OrigNIFactory;
static void X3_BuilderSetCloningSupported(id self, SEL _cmd, BOOL supported) {
    if (!supported) { ((void (*)(id, SEL))objc_msgSend)(self, sel_registerName("setCloningNotSupported")); return; }
    Ivar lk = class_getInstanceVariable(object_getClass(self), "_lock"), nc = class_getInstanceVariable(object_getClass(self), "_lock_noCloning");
    if (!lk || !nc) return;
    os_unfair_lock_t l = (os_unfair_lock_t)((char *)(__bridge void *)self + ivar_getOffset(lk));
    os_unfair_lock_lock(l);
    *((BOOL *)((char *)(__bridge void *)self + ivar_getOffset(nc))) = NO;          // 16.2: _lock_cloningSupported = YES, _lock_cloningSet = YES
    os_unfair_lock_unlock(l);
}
static void X3_NIFactoryTransform(id self, SEL _cmd, id builder) {
    ((void (*)(id, SEL, id))gX3OrigNIFactory)(self, _cmd, builder);
    if (!BP_OnName("cloningsupported") || !builder) return;
    id config = BPX_IvarObj(builder, "_configuration");
    SEL sR = sel_registerName("isRestrictedAirPlayDisplay");
    id ident = BPX_Obj0(config, "identity");
    if (!ident || ![ident respondsToSelector:sR]) return;
    BOOL restricted = ((BOOL (*)(id, SEL))objc_msgSend)(ident, sR);
    if (restricted) BPX_SetObj1(builder, "setUniqueIdentifier:", @"com.apple.springboard.noninteractive.PA2D");
    ((void (*)(id, SEL, BOOL))objc_msgSend)(builder, sel_registerName("setCloningSupported:"), !restricted);
    BP_Log(@"[x3] non interactive display %@: %@, cloning %s", ident, restricted ? @"restricted AirPlay display (PA2D)" : @"unrestricted", restricted ? "not supported" : "supported");
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
    // 16.2 displayPreferencesForDisplayController: on both policies and the controller's transform (item 3 of specs/DISPLAY-LEFTOVERS-0.7.9.md)
    Class ni = NSClassFromString(@"SBNonInteractiveDisplayControllerPolicy");
    SEL sPrefs = sel_registerName("displayPreferencesForDisplayController:");
    BOOL a = class_addMethod(pol, sPrefs, (IMP)X3_ExtendedPolicyPrefs, "@24@0:8@16");
    BOOL b = ni && class_addMethod(ni, sPrefs, (IMP)X3_NonInteractivePolicyPrefs, "@24@0:8@16");
    gX3OrigCtlTransform = BPX_Replace(ctl, "transformDisplayConfiguration:withBuilder:", (IMP)X3_CtlTransform);
    BP_Log(@"[x3] displayPreferencesForDisplayController: extended %d non interactive %d, controller transform %s (switch modetransform)", (int)a, (int)b, gX3OrigCtlTransform ? "installed" : "NOT installed (selector missing)");
    {
        Class bld = NSClassFromString(@"FBSDisplayConfigurationBuilder"), fac = NSClassFromString(@"SBNonInteractiveDisplayControllerPolicyFactory");
        BOOL ok2 = bld && fac && class_getInstanceMethod(bld, sel_registerName("setCloningNotSupported")) && class_getInstanceMethod(fac, sel_registerName("transformDisplayForControllersWithBuilder:"));
        if (ok2) {
            if (!class_getInstanceMethod(bld, sel_registerName("setCloningSupported:"))) class_addMethod(bld, sel_registerName("setCloningSupported:"), (IMP)X3_BuilderSetCloningSupported, "v20@0:8B16");
            gX3OrigNIFactory = BPX_Replace(fac, "transformDisplayForControllersWithBuilder:", (IMP)X3_NIFactoryTransform);
        }
        BP_Log(@"[x3] setCloningSupported: / non interactive policy factory %s (switch cloningsupported)", (ok2 && gX3OrigNIFactory) ? "installed" : "NOT installed (class or selector missing)");
    }
    BP_Log(@"[x3] monitor mode choice installed (switches modecriteria, modebase, modelogical, modetransform)");
}
#pragma clang diagnostic pop
