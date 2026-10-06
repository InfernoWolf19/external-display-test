TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AudioRouteProbe

AudioRouteProbe_FILES = Probe.c SpringBoardProbe.m
AudioRouteProbe_CFLAGS = -Wno-deprecated-declarations
AudioRouteProbe_OBJCFLAGS = -fobjc-arc
AudioRouteProbe_FRAMEWORKS = CoreFoundation Foundation CydiaSubstrate

include $(THEOS_MAKE_PATH)/tweak.mk
