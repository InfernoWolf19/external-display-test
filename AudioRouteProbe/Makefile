TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AudioRouteProbe

AudioRouteProbe_FILES = Probe.c
AudioRouteProbe_CFLAGS = -fno-objc-arc -Wno-deprecated-declarations
AudioRouteProbe_FRAMEWORKS = CoreFoundation CydiaSubstrate

include $(THEOS_MAKE_PATH)/tweak.mk
