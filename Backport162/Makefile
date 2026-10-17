TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Backport162 Backport162AV Backport162BBD Backport162PTR

Backport162_FILES = Tweak.x Group4Connect.m Group4Focus.x G1B.x G1C.x G1D.x PIPStop.x G2C.x G2D.x G2E.x G2F.x G2.x G2B.m G3.x G3B.x G3C.x G4B.x EDE.x BPCrash.m
Backport162_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -ferror-limit=0
Backport162_FRAMEWORKS = Foundation CoreGraphics UIKit QuartzCore

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

include $(THEOS_MAKE_PATH)/tweak.mk
