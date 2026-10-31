TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Backport162 Backport162AV Backport162BBD Backport162PTR Backport162SMT Backport162SPK Backport162UIK

Backport162_FILES = Tweak.x Group4Connect.m Group4Focus.x G1B.x G1C.x G1D.x PIPStop.x G2C.x G2D.x G2E.x G2F.x G2G.x G2.x G2B.m G3.x G3B.x G3C.x G4B.x EDE.x G2I.x G2H.x X2Overlay.x X9Pin.x X7Keyboard.x X6InCall.x X5Recording.x X3Mode.x BPCrash.m RPT.x Y1Workspace.x P1Drag.m Y2Gestures.x Z1Diag.x P1VC.m P1SW.m Y3StatusBar.x Y4Home.x Y5Apps.x Y6Portal.x Y7Requests.x Y8Layout.x Y9Misc.x Y10Pip.x Y11Modifiers.x Y12Dock.x Y13Fluid.x Y14Open.x Y15InCall.x Y16Contingency.x Y17Snapshot.x Z2OrientTraits.m Z2OrientDelegate.m Y18IndirectPan.x Y19PanDelegates.x Y20Kbd.x Y21Modifiers.x Y22Modifiers.x Y23Home.x Y24Drag.x Y25Workspace.x Y26Classic.x Y27Views.x Y28Keyboard.x Y29Blur.x Y30Snapshot.x Y31Misc.x
Backport162_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -ferror-limit=0
Backport162_FRAMEWORKS = Foundation CoreGraphics UIKit QuartzCore
# RPT.x (Send logs, SpringBoard half) gzips the report with zlib
Backport162_LIBRARIES = z

Backport162AV_FILES = AV.x
Backport162AV_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -ferror-limit=0
Backport162AV_FRAMEWORKS = Foundation UIKit

# backboardd half (filter: the backboardd executable; arm64e only, the addresses are those of 20A8372; reboot userspace after installing)
Backport162BBD_FILES = BBD.x
Backport162BBD_ARCHS = arm64e
Backport162BBD_CFLAGS = -fobjc-arc -Wall -Werror -Wno-deprecated-declarations
Backport162BBD_FRAMEWORKS = Foundation

# pointeruid half (filter: the pointeruid executable; arm64e only, build 20A8372 only; killall pointeruid or reboot userspace after installing)
Backport162PTR_FILES = PTR.x
Backport162PTR_ARCHS = arm64e
Backport162PTR_CFLAGS = -fobjc-arc -Wall -Werror -Wno-deprecated-declarations
Backport162PTR_FRAMEWORKS = Foundation UIKit

# Stage Manager toggle (merged StageManagerToggle 1.0.0; filter: SpringBoard + the Preferences app, Backport162SMT.plist; switch smtoggle)
Backport162SMT_FILES = SMT.x
Backport162SMT_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -ferror-limit=0
Backport162SMT_FRAMEWORKS = Foundation

# audio daemon half (merged SpeakerPicker 1.1.0~idle1; filter: the audiomxd and mediaserverd executables, build 20A8372 only; plain C, no ARC; restart the audio daemons or reboot userspace after installing; switch speaker)
Backport162SPK_FILES = SPK.c
Backport162SPK_CFLAGS = -Wno-deprecated-declarations
Backport162SPK_LDFLAGS = -lobjc
Backport162SPK_FRAMEWORKS = CoreFoundation CydiaSubstrate

# in-app UIKit half (UIK.m; filter: com.apple.UIKit, Backport162UIK.plist; runs inside apps only, build 20A8372 only; no addresses, plain ObjC runtime hooks, so both arm64 and arm64e; specs/UIKIT-APP-0.7.9.md; switches uik, uik_screenbounds, uik_keyboard, uik_screenlife). Relaunch an app after installing.
Backport162UIK_FILES = UIK.m
Backport162UIK_CFLAGS = -fobjc-arc -Wall -Werror -Wno-deprecated-declarations
Backport162UIK_FRAMEWORKS = Foundation UIKit

# BP_ONLY_PREFS=1 (CI only) skips the tweak dylibs and builds just the Settings pane; BP_SKIP_PREFS=1 skips the pane.
ifneq ($(BP_ONLY_PREFS),1)
include $(THEOS_MAKE_PATH)/tweak.mk
endif

# Settings pane "Backport162" (PreferenceLoader bundle; Send logs / Share last report; UI only, the work is RPT.x in SpringBoard; specs/SEND-LOGS-0.7.9.md).
# Loaded into Preferences.app only when the pane is opened. The Preferences framework is private: it is linked when the SDK has it, otherwise dyld resolves PSListController at run time
# (Preferences.app has the framework loaded); the classes used are declared in Backport162PrefsRootListController.h.
ifneq ($(BP_SKIP_PREFS),1)
BUNDLE_NAME = Backport162Prefs
Backport162Prefs_FILES = Backport162Prefs/Backport162PrefsRootListController.m
Backport162Prefs_INSTALL_PATH = /Library/PreferenceBundles
Backport162Prefs_RESOURCE_DIRS = Backport162Prefs/Resources
Backport162Prefs_CFLAGS = -fobjc-arc -Wall -Wno-deprecated-declarations -ferror-limit=0
Backport162Prefs_FRAMEWORKS = Foundation UIKit
ifneq ($(wildcard $(SYSROOT)/System/Library/PrivateFrameworks/Preferences.framework),)
Backport162Prefs_PRIVATE_FRAMEWORKS = Preferences
else
Backport162Prefs_LDFLAGS = -Wl,-undefined,dynamic_lookup
endif
include $(THEOS_MAKE_PATH)/bundle.mk
endif
