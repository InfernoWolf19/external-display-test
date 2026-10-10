TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Backport162

Backport162_FILES = Tweak.x Group4Connect.m Group4Focus.x G1B.x G1C.x G2.x G2B.m G3.x G3B.x G4B.x
Backport162_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -ferror-limit=0
Backport162_FRAMEWORKS = Foundation CoreGraphics UIKit QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk
