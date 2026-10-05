TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ExtendedDisplayEnabler

ExtendedDisplayEnabler_FILES = Tweak.x
ExtendedDisplayEnabler_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
ExtendedDisplayEnabler_FRAMEWORKS = UIKit

include $(THEOS_MAKE_PATH)/tweak.mk
