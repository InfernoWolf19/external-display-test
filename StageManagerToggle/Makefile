TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless
INSTALL_TARGET_PROCESSES = SpringBoard Preferences

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = StageManagerToggle

StageManagerToggle_FILES = Tweak.x
StageManagerToggle_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
StageManagerToggle_FRAMEWORKS = Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
