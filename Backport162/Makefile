TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Backport162

Backport162_FILES = Tweak.x Group4Connect.m
Backport162_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
Backport162_FRAMEWORKS = Foundation CoreGraphics

include $(THEOS_MAKE_PATH)/tweak.mk
