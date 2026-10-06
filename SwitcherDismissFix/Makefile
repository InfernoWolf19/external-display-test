TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = SwitcherDismissFix

SwitcherDismissFix_FILES = Tweak.x
SwitcherDismissFix_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
SwitcherDismissFix_FRAMEWORKS = Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
