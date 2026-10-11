// Shared between Tweak.x and the other Backport162 source files.
#import <Foundation/Foundation.h>

// Feature switches. Every feature is on by default (except the few marked opt-in in Tweak.x kOptIn);
// <jbroot>/tmp/Backport162.off.<name> turns one off and <jbroot>/tmp/Backport162.off turns everything off.
// Opt-in features need <jbroot>/tmp/Backport162.on.<name>. The names are in kFeatureNames (Tweak.x) and README.md.
// A package that checks sub-switches by name uses BP_OnName() / BP_OptInName() (same files, same kill switch).
enum {
    // group 4 (0.5.x)
    F_SCALE, F_AUTOHOST, F_BLANK, F_DISCONNECT, F_DISCSWITCH, F_ACTIVEDISPLAY, F_GESTUREGATE, F_LOCKEDPTR, F_NOWINDOW, F_DIRECTHOOK,
    // group 1b (modifier / event / response classes), group 1c (16.2 modifier rewrites), group 2 (layout data), group 2b (switcher view)
    F_G1B, F_G1B_APPTOAPP, F_G1C, F_G1C_PILES, F_G2, F_G2B, F_G2BPROTO, F_G2BLAYOUT, F_G2BKEYS, F_G2BAPERTURE, F_G2BTONGUE, F_CGREGION,
    // group 3 (plumbing)
    F_G3HANDLE, F_G3SNAPSHOT, F_G3TOPAFF, F_G3SWITCHER, F_G3CANVAS, F_G3EMBEDDED, F_G3BOOTORIENT,
    // group 3b (reconstruction)
    F_G3B_BANNER, F_G3B_MENU, F_G3B_PIP, F_G3B_KBWINDOW, F_G3B_STATUSBAR, F_G3B_ORIENT, F_G3B_GRID, F_G3B_GUIDE, F_G3B_SPLIT, F_G3B_PREFLIGHTLOG, F_G3B_AXROLES,
    // group 4b (reconstruction)
    F_CLONEMIRROR, F_EDU, F_EDUNATIVE, F_PRESUBSET, F_DEFERACT, F_LOCKEDPTR2, F_MIGRATE, F_FOCUSLOCK, F_ARRANGE, F_METHODOLOGY0,
    // group 3c (top-affordance Zoom on a full-screen app)
    F_G3C,
    F_COUNT
};

BOOL BP_On(int feature);
BOOL BP_OnName(const char *name);       // default-on switch by name: not killed and no Backport162.off.<name>
BOOL BP_OptInName(const char *name);    // opt-in switch by name: BP_OnName(name) and Backport162.on.<name> exists
void BP_Log(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);
BOOL BP_LogEnabled(void);               // cheap test (cached one second): lets callers skip building log arguments
